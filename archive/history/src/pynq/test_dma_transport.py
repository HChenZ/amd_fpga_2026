"""Offline DMA ownership/deadline/ABI tests; fake payloads are not crypto evidence."""
import struct
import sys
from pathlib import Path
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from src.pynq.dma_transport import (DMATransport, DMAError, ProtocolError, RemoteError,
    encode_request, decode_response, REQUEST, RESPONSE, IDENTITY, PynqSimpleDMA, DMABackend,
    dma_configuration)


class Clock:
    def __init__(self): self.now = 0
    def __call__(self): self.now += .0001; return self.now
    def sleep(self, n): self.now += n


class Buffer(list):
    def __init__(self, n, events):
        super().__init__([0]*n)
        self.events = events
        self.freed = False
        self.physical_address = 0x100000
    def __setitem__(self, index, value):
        if isinstance(index, slice) and isinstance(value, int):
            value = [value]*len(self[index])
        super().__setitem__(index, value)
    def flush(self): self.events.append('flush')
    def invalidate(self): self.events.append('invalidate')
    def freebuffer(self): self.freed = True; self.events.append('free')


class Control:
    def __init__(self):
        self.regs = {0:IDENTITY,4:2,8:1,0xc:0,0x10:0,0x14:1024,0x18:1024,0x1c:15,0x20:0}
        for mode, cap in enumerate((32,16,32,1024)):
            self.regs[0x30+mode*8]=cap;self.regs[0x34+mode*8]=cap
    def read(self, offset): return self.regs.get(offset,0)
    def write(self, offset, value):
        self.regs[offset] = value
        if offset == 8: self.regs[0x20] = 0 if value else 1


class DMA:
    def __init__(self, events):
        self.events=events;self.safe=True;self.hang=False;self.mutate=lambda x:x
        self.status=0;self.throw_start=False
    def quiesce(self, deadline): self.events.append('quiesce');return self.safe
    def start_receive(self, b, n): self.events.append('rx');self.rx=b
    def start_send(self, b, n):
        self.events.append('tx')
        if self.throw_start: raise DMAError('start error')
        q=REQUEST.unpack(bytes(b[:48]));magic,ver,flags,epoch,rid,op,mode,alen,dlen,cap,tlen=q
        payload=bytes(cap) if not self.status else b''
        packet=RESPONSE.pack(b'D01R',2,1 if not self.status else 0,epoch,rid,self.status,
                             op,mode,len(payload),123 if not self.status else 0)+payload
        packet=self.mutate(packet)
        self.length=len(packet)
        self.rx[:len(packet)] = packet
    def poll(self): return not self.hang,self.length


class Tests(unittest.TestCase):
    def setUp(self):
        self.events=[];self.buffers=[];self.clock=Clock();self.control=Control();self.dma=DMA(self.events)
        def alloc(shape,dtype):
            b=Buffer(shape[0],self.events);self.buffers.append(b);return b
        self.t=DMATransport(self.control,self.dma,alloc,clock=self.clock,sleep=self.clock.sleep,timeout=.05)
        self.t.recover(epoch=17)
        self.events.clear()
    def request(self, **kwargs):
        args=dict(operation=1,mode=3,key=bytes(16),nonce=bytes(16),ad=b'a',data=b'abc')
        args.update(kwargs)
        return self.t.transact(**args)
    def test_order_visibility_release(self):
        r=self.request()
        self.assertEqual(r.cycles,123)
        self.assertLess(self.events.index('rx'),self.events.index('tx'))
        self.assertEqual(self.events[:2],['flush','flush'])
        self.assertLess(self.events.index('invalidate'),self.events.index('quiesce'))
        self.assertLess(self.events.index('quiesce'),self.events.index('free'))
        self.assertTrue(all(b.freed and not any(b) for b in self.buffers))
    def test_modes_and_capacity(self):
        self.request(mode=4,data=bytes(1024),ad=bytes(1024))
        for mode in (1,3): self.request(mode=mode,data=bytes(32),ad=bytes(32))
        self.request(mode=2,data=bytes(16),ad=bytes(16))
        for mode,size in ((1,33),(2,17),(3,33),(4,1025)):
            with self.subTest(mode=mode),self.assertRaises(ValueError):self.request(mode=mode,data=bytes(size))

    def test_immutable_request_snapshot_before_control_callbacks(self):
        data=bytearray(b'abc')
        original=self.control.read
        changed=[False]
        def read(offset):
            if offset==0x20 and not changed[0]:
                data.extend(b'changed')
                changed[0]=True
            return original(offset)
        self.control.read=read
        result=self.request(data=data)
        self.assertEqual(len(result.payload),19)
        self.assertEqual(data,b'abcchanged')
        self.assertFalse(self.t.needs_recovery)

    def test_capacity_is_bytes_not_array_elements(self):
        import array
        with self.assertRaises(ValueError):self.request(mode=1,data=array.array('I',range(9)))
        self.assertFalse(self.events)
    def test_no_implicit_recovery(self):
        self.t.needs_recovery=True
        with self.assertRaises(DMAError):self.request()
        self.assertEqual(self.events,[])
    def test_timeout_quiesces(self):
        self.dma.hang=True
        with self.assertRaises(TimeoutError):self.request()
        self.assertTrue(self.t.needs_recovery)
        self.assertTrue(all(b.freed for b in self.buffers))
    def test_failed_quiescence_retains_and_blocks(self):
        self.dma.safe=False
        with self.assertRaises(DMAError):self.request()
        self.assertEqual(len(self.t.retained),2)
        self.assertFalse(any(b.freed for b in self.buffers))
        with self.assertRaises(DMAError):self.request()
        self.dma.safe=True;self.t.recover(epoch=18)
        self.assertFalse(self.t.retained)
        self.assertTrue(all(b.freed for b in self.buffers))
    def test_start_failure_quiesces(self):
        self.dma.throw_start=True
        with self.assertRaises(DMAError):self.request()
        self.assertTrue(self.t.needs_recovery)
        self.assertIn('quiesce',self.events)

    def test_interrupt_after_rx_start_aborts_and_quiesces(self):
        def interrupt(*args):raise KeyboardInterrupt()
        self.dma.start_send=interrupt
        with self.assertRaises(KeyboardInterrupt):self.request()
        self.assertTrue(self.t.needs_recovery)
        self.assertEqual(self.control.read(8),1)
        self.assertTrue(all(b.freed for b in self.buffers))

    def test_interrupt_inside_cleanup_retains_buffers(self):
        original=self.dma.quiesce
        def interrupt(*args):raise KeyboardInterrupt()
        self.dma.quiesce=interrupt
        with self.assertRaises(DMAError):self.request()
        self.assertTrue(self.t.needs_recovery)
        self.assertEqual(len(self.t.retained),2)
        self.assertFalse(any(b.freed for b in self.buffers))
        self.dma.quiesce=original
        self.t.recover(epoch=18)
        self.assertTrue(all(b.freed for b in self.buffers))
    def test_identity_mismatch_quarantine(self):
        for offset in (0,4,8,16,28,32,36):
            with self.subTest(offset=offset):
                self.dma.mutate=lambda p,o=offset:p[:o]+bytes([p[o]^1])+p[o+1:]
                with self.assertRaises(ProtocolError):self.request()
                self.assertTrue(self.t.needs_recovery)
                self.t.recover(epoch=self.t.epoch+1)
    def test_failure_has_no_payload_flags_cycles(self):
        for status in range(1,7):
            self.dma.status=status
            with self.subTest(status=status),self.assertRaises(RemoteError):
                self.request(operation=2,tag=bytes(16))
        self.assertFalse(self.t.needs_recovery)
    def test_failure_payload_rejected(self):
        self.dma.status=1
        self.dma.mutate=lambda p:p+bytes(1)
        with self.assertRaises(ProtocolError):self.request(operation=2,tag=bytes(16))
    def test_simulated_flag_rejected(self):
        self.dma.mutate=lambda p:p[:6]+b'\x03'+p[7:]
        with self.assertRaises(ProtocolError):self.request()
    def test_capability_identity(self):
        for offset,value in ((0,0),(4,1),(0x1c,0),(0x1c,16),(0x14,1025),(0x30,2000)):
            old=self.control.regs[offset];self.control.regs[offset]=value
            with self.subTest(offset=offset),self.assertRaises(ProtocolError):self.t.recover(epoch=19)
            self.control.regs[offset]=old
    def test_epoch_must_change(self):
        for ep in (0,17,2**64):
            with self.assertRaises(ValueError):self.t.recover(epoch=ep)
    def test_request_id_exhaustion(self):
        self.t.request_id=2**64-1
        with self.assertRaises(ValueError):self.request()
        self.assertEqual(self.events,[])
    def test_single_client(self):
        self.t.lock.acquire()
        try:
            with self.assertRaises(DMAError):self.request()
            with self.assertRaises(DMAError):self.t.recover(epoch=18)
        finally:self.t.lock.release()
        with self.assertRaises(DMAError):DMATransport(self.control,self.dma,self.t.allocate)
    def test_deadlines_finite(self):
        for t in (0,-1,float('nan'),float('inf')):
            with self.subTest(timeout=t),self.assertRaises(ValueError):self.request(timeout=t)
    def test_codec_roundtrip_layout(self):
        q=encode_request(2**63,2**63+1,2,4,bytes(16),bytes(16),b'abc',b'd',bytes(16))
        self.assertEqual(len(q),100)
        self.assertEqual(q[:8],b'D01Q\x02\x00\x00\x00')
        self.assertEqual(REQUEST.unpack(q[:48])[3:5],(2**63,2**63+1))
    def test_codec_invalid_inputs(self):
        for key,nonce,tag in [(b'',bytes(16),b''),(bytes(16),b'',b''),(bytes(16),bytes(16),b'x')]:
            with self.assertRaises(ValueError):encode_request(1,1,1,1,key,nonce,b'',b'',tag)
    def test_response_cycles64(self):
        p=RESPONSE.pack(b'D01R',2,1,1,2,0,2,4,0,2**63)
        self.assertEqual(decode_response(p,1,2,2,4,0).cycles,2**63)
        with self.assertRaises(ProtocolError):decode_response(p[:6]+b'\x00'+p[7:],1,2,2,4,0)
    def test_backend_host_api(self):
        from src.pynq.ascon_host_api import AsconHost,AuthenticationError
        h=AsconHost(DMABackend(self.t,'ise'))
        result=h.encrypt(bytes(16),bytes(16),b'',b'abc')
        self.assertEqual(result.cycles,123)
        self.dma.status=1
        with self.assertRaises(AuthenticationError):h.decrypt(bytes(16),bytes(16),b'',bytes(3),bytes(16))
    def test_pynq_register_order_and_bounded_reset(self):
        class MMIO:
            def __init__(self):self.regs={4:1,0x34:1};self.writes=[]
            def read(self,o):return self.regs.get(o,0)
            def write(self,o,v):self.writes.append((o,v));self.regs[o]=v
        mm=MMIO();d=PynqSimpleDMA(mm,self.clock,self.clock.sleep)
        b=Buffer(64,self.events)
        d.start_receive(b,64);d.start_send(b,64)
        self.assertEqual(mm.writes[4],(0x58,64))
        self.assertEqual(mm.writes[9],(0x28,64))
        self.assertFalse(d.quiesce(self.clock()+.01))

    def delayed_endpoint(self, polls, status=0):
        original=self.control.read
        original_poll=self.dma.poll
        remaining=[0]
        enabled=[True]
        self.dma.status=status
        def poll():
            result=original_poll()
            if enabled[0]:remaining[0]=polls;enabled[0]=False
            return result
        def read(offset):
            if offset==0x20 and remaining[0]:
                remaining[0]-=1
                self.events.append('scrub')
                return 2
            return original(offset)
        self.control.read=read;self.dma.poll=poll

    def test_scrub_waits_before_return_and_release(self):
        self.delayed_endpoint(8)
        self.request(mode=4)
        self.assertEqual(self.events.count('scrub'),8)
        self.assertLess(max(i for i,e in enumerate(self.events) if e=='scrub'),self.events.index('free'))
        self.request(mode=4)
        self.assertFalse(self.t.needs_recovery)

    def test_remote_failure_also_waits_for_scrub(self):
        self.delayed_endpoint(8,status=1)
        with self.assertRaises(RemoteError):self.request(operation=2,tag=bytes(16),mode=4)
        self.assertEqual(self.events.count('scrub'),8)
        self.assertFalse(self.t.needs_recovery)

    def test_scrub_deadline_aborts_cpu_then_quiesces(self):
        self.delayed_endpoint(1000)
        original=self.dma.quiesce
        def quiesce(deadline):
            self.assertEqual(self.control.read(8),1)
            return original(deadline)
        self.dma.quiesce=quiesce
        with self.assertRaises(TimeoutError):self.request(mode=4)
        self.assertTrue(self.t.needs_recovery)
        self.assertTrue(all(b.freed for b in self.buffers))

    def test_transient_busy_before_submit(self):
        old=self.control.read;polls=[5]
        def read(offset):
            if offset==0x20 and polls[0]:polls[0]-=1;return 2
            return old(offset)
        self.control.read=read
        self.request()
        self.assertEqual(polls[0],0)

    def test_close_releases_only_after_halted_proof(self):
        self.dma.safe=False
        with self.assertRaises(DMAError):self.request()
        with self.assertRaises(DMAError):self.t.close()
        self.assertFalse(any(b.freed for b in self.buffers))
        self.dma.safe=True;self.t.close()
        self.assertTrue(all(b.freed for b in self.buffers))
        self.assertTrue(self.t.needs_recovery)

    def test_close_cannot_recover_without_process_ownership(self):
        self.t.close()
        self.assertTrue(self.t.closed)
        self.t.close()  # idempotent, no further hardware transaction
        with self.assertRaises(DMAError):self.t.recover(epoch=18)
        with self.assertRaises(DMAError):self.request()
        new=DMATransport(self.control,self.dma,self.t.allocate,clock=self.clock,sleep=self.clock.sleep)
        new.recover(epoch=18)
        self.assertFalse(new.closed)

    def test_raw_dma_completed_events_and_actual_length(self):
        class Registers:
            def __init__(self):self.regs={4:1,0x34:1};self.writes=[]
            def read(self,o):return self.regs.get(o,0)
            def write(self,o,v):
                self.writes.append((o,v))
                if o in (4,0x34):self.regs[o]=self.regs.get(o,0)&~v
                elif o in (0,0x30) and v==1:self.regs[o+4]=0
                elif o==0 and v==4:self.regs[0]=0;self.regs[4]=1;self.regs[0x34]=1
                else:self.regs[o]=v
        mm=Registers();d=PynqSimpleDMA(mm,self.clock,self.clock.sleep)
        b=Buffer(96,self.events)
        with self.assertRaises(DMAError):d.poll()
        d.start_receive(b,96);d.start_send(b,80)
        mm.regs[4]=2;mm.regs[0x34]=2
        self.assertEqual(d.poll(),(False,0))  # idle alone is not a fresh completion event
        mm.regs[4]=0x1002;mm.regs[0x34]=0x1002;mm.regs[0x58]=48
        self.assertEqual(d.poll(),(True,48))  # error response shorter than receive capacity
        self.assertTrue(d.quiesce(self.clock()+.01))
        d.start_receive(b,96);d.start_send(b,80)
        self.assertEqual(d.poll(),(False,0))  # IOC was cleared; no stale replay
        mm.regs[0x34]=0x20
        with self.assertRaises(DMAError):d.poll()

    def test_hwh_configuration_limits_and_alignment(self):
        p=dict(c_include_sg='0',c_micro_dma='0',c_include_mm2s='1',c_include_s2mm='1',
               c_sg_length_width='14',c_m_axi_mm2s_data_width='64',c_m_axi_s2mm_data_width='128',
               c_include_mm2s_dre='0',c_include_s2mm_dre='0')
        cfg=dma_configuration(p)
        self.assertEqual(cfg,dict(max_transfer=16383,tx_alignment=8,rx_alignment=16))
        for field,value in [('c_include_sg','1'),('c_micro_dma','1'),('c_include_mm2s','0'),
                            ('c_sg_length_width','0'),('c_m_axi_s2mm_data_width','7')]:
            bad=dict(p);bad[field]=value
            with self.subTest(field=field),self.assertRaises(DMAError):dma_configuration(bad)
        with self.assertRaises(DMAError):dma_configuration(None)
        d=PynqSimpleDMA(self.control,self.clock,self.clock.sleep,**cfg)
        b=Buffer(100,self.events);b.physical_address+=4
        with self.assertRaises(ValueError):d.start_send(b,80)
        b.physical_address-=4
        d.max_transfer=63
        with self.assertRaises(ValueError):d.start_send(b,80)


if __name__=='__main__':unittest.main(verbosity=2)
