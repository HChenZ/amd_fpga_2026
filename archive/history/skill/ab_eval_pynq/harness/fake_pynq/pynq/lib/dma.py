"""Faithful-in-behaviour copy of the PYNQ 2.7 simple-DMA driver semantics (unbounded spins
included), running on the fake register model. Grading only."""
from pynq import DefaultIP

DMA_TYPE_TX, DMA_TYPE_RX = 1, 0


class _SDMAChannel:
    def __init__(self, mmio, max_size, width, tx_rx, dre):
        self._mmio, self._max_size, self._align, self._dre = mmio, max_size, width, dre
        self._offset = 0x30 if tx_rx == DMA_TYPE_RX else 0
        self._flush_before = tx_rx == DMA_TYPE_TX
        self._active_buffer = None
        self._first_transfer = True
        self.transferred = 0
        self.start()

    @property
    def running(self):
        return self._mmio.read(self._offset + 4) & 0x01 == 0x00

    @property
    def idle(self):
        return self._mmio.read(self._offset + 4) & 0x02 == 0x02

    @property
    def error(self):
        return self._mmio.read(self._offset + 4) & 0x70 != 0x0

    def start(self):
        self._mmio.write(self._offset, 0x0001)
        while not self.running:
            pass
        self._first_transfer = True

    def stop(self):
        self._mmio.write(self._offset, 0x0000)

    def transfer(self, array, start=0, nbytes=0):
        if not self.running:
            raise RuntimeError('DMA channel not started')
        if not self.idle and not self._first_transfer:
            raise RuntimeError('DMA channel not idle')
        if nbytes == 0:
            nbytes = array.nbytes - start
        if nbytes > self._max_size:
            raise ValueError('Transfer size is {} bytes, which exceeds the maximum DMA buffer size {}.'.format(
                nbytes, self._max_size))
        if not self._dre and ((array.physical_address + start) % self._align) != 0:
            raise RuntimeError('DMA does not support unaligned transfers')
        if self._flush_before:
            array.flush()
        self.transferred = 0
        self._mmio.write(self._offset + 0x18, (array.physical_address + start) & 0xffffffff)
        self._mmio.write(self._offset + 0x1C, ((array.physical_address + start) >> 32) & 0xffffffff)
        self._mmio.write(self._offset + 0x28, nbytes)
        self._active_buffer = array
        self._first_transfer = False

    def wait(self):
        if not self.running:
            raise RuntimeError('DMA channel not started')
        while True:
            error = self._mmio.read(self._offset + 4)
            if self.error:
                if error & 0x10:
                    raise RuntimeError('DMA Internal Error (transfer length 0?)')
                if error & 0x20:
                    raise RuntimeError('DMA Slave Error (cannot access memory map interface)')
                if error & 0x40:
                    raise RuntimeError('DMA Decode Error (invalid address)')
            if self.idle:
                break
        if not self._flush_before:
            self._active_buffer.invalidate()
        self.transferred = self._mmio.read(self._offset + 0x28)


class DMA(DefaultIP):
    bindto = ['xilinx.com:ip:axi_dma:7.1']

    def __init__(self, description, *args, **kwargs):
        super().__init__(description)
        p = description['parameters']
        self.buffer_max_size = (1 << int(p.get('c_sg_length_width', 26))) - 1
        width = int(p.get('c_m_axi_mm2s_data_width', 32)) >> 3
        self.sendchannel = _SDMAChannel(self.mmio, self.buffer_max_size, width, DMA_TYPE_TX,
                                        bool(int(p.get('c_include_mm2s_dre', 0))))
        self.recvchannel = _SDMAChannel(self.mmio, self.buffer_max_size, width, DMA_TYPE_RX,
                                        bool(int(p.get('c_include_s2mm_dre', 0))))
