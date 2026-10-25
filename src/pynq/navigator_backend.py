"""Navigator preparation: validated driver injection, no invented AXI registers.

This adapter never programs the FPGA or falls back to reference encryption.
A future driver must implement Transport against a reviewed physical protocol.
Mock drivers retain simulated=True through the existing MailboxBackend.
"""
import hashlib
import json
import math
from pathlib import Path
import time

if __package__:
    from .ascon_host_api import AsconError, AsconHost, BackendProtocolError, BackendTimeoutError
    from .mailbox_backend import Capabilities, MailboxBackend, Transport
else:
    from ascon_host_api import AsconError, AsconHost, BackendProtocolError, BackendTimeoutError
    from mailbox_backend import Capabilities, MailboxBackend, Transport


class NotConfiguredError(AsconError):
    status = 'NOT_CONFIGURED'


def read_profile(path):
    value = json.loads(Path(path).read_text(encoding='utf-8'))
    if not isinstance(value,dict) or value.get('schema_version') != 1:
        raise ValueError('unsupported navigator profile')
    if value.get('part') != 'xc7z020clg400-1':
        raise ValueError('navigator profile must preserve the approved -1 target')
    return value


def validate_overlay(profile, overlay):
    """Read-only check of a caller-loaded overlay and release manifest, before I/O.

    Addresses must match the HWH-derived ip_dict. No vendor GPIO address is reused
    as this project's mailbox. Files/hashes document provenance, not authenticity.
    """
    if profile.get('status') != 'configured':
        raise NotConfiguredError('NOT_CONFIGURED: physical mailbox and overlay are pending')
    if not profile.get('part') or not profile.get('design_source') or not profile.get('protocol_revision') or not profile.get('firmware_id'):
        raise NotConfiguredError('NOT_CONFIGURED: reviewed design/protocol provenance is required')
    if profile.get('part') != 'xc7z020clg400-1':
        raise ValueError('unapproved target part')
    if overlay is None or not callable(getattr(overlay,'is_loaded',None)) or not overlay.is_loaded():
        raise NotConfiguredError('NOT_CONFIGURED: caller must provide an already loaded overlay')
    artifacts = profile.get('artifacts')
    if not isinstance(artifacts,dict) or set(artifacts) != {'bit','hwh','firmware'}:
        raise NotConfiguredError('NOT_CONFIGURED: bit/hwh/firmware release manifest required')
    for kind, item in artifacts.items():
        if not isinstance(item,dict) or not isinstance(item.get('path'),str) or not isinstance(item.get('sha256'),str):
            raise ValueError('invalid release artifact entry')
        path = Path(item['path'])
        if len(item['sha256'])!=64 or any(c not in '0123456789abcdef' for c in item['sha256']):
            raise ValueError('invalid artifact SHA256')
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest()!=item['sha256']:
            raise BackendProtocolError('navigator release artifact integrity check failed')
    bit, hwh = (Path(artifacts[k]['path']).resolve() for k in ('bit','hwh'))
    if bit.suffix.lower()!='.bit' or hwh.suffix.lower()!='.hwh' or bit.with_suffix('.hwh')!=hwh:
        raise ValueError('bit/hwh must be a matching basename pair')
    if Path(getattr(overlay,'bitfile_name','')).resolve()!=bit:
        raise BackendProtocolError('loaded overlay differs from release manifest')
    bindings = profile.get('ip_bindings')
    if not isinstance(bindings,dict) or set(bindings) != {'control','mailbox'}:
        raise NotConfiguredError('NOT_CONFIGURED: HWH control/mailbox bindings required')
    ip_dict = getattr(overlay,'ip_dict',{})
    ranges = []
    for item in bindings.values():
        if not isinstance(item,dict):
            raise ValueError('invalid IP binding')
        name, base, size = item.get('name'),item.get('phys_addr'),item.get('addr_range')
        if not isinstance(name,str) or type(base) is not int or type(size) is not int:
            raise ValueError('binding requires an IP name, integer address and range')
        if base<0 or base%4 or size<=0 or size%4 or base+size>2**32:
            raise ValueError('unaligned or out-of-range PS AXI window')
        actual = ip_dict.get(name,{})
        if actual.get('phys_addr')!=base or actual.get('addr_range')!=size:
            raise BackendProtocolError('configured IP window does not match HWH')
        ranges.append((base,base+size))
    if max(ranges[0][0],ranges[1][0]) < min(ranges[0][1],ranges[1][1]):
        raise ValueError('control/mailbox windows overlap')


class NavigatorTransport(Transport):
    """Validated seam for a future real driver; absent configuration fails closed.

    driver is an implementation of the existing Transport, responsible for MMIO,
    atomic publish, firmware loading verification, cache/barriers and recovery.
    No such hardware implementation exists in this preparation change.
    """
    def __init__(self, profile=None, *, driver=None, overlay=None, clock=time.monotonic):
        self.profile = profile or {}
        self.driver, self.overlay, self.clock = driver, overlay, clock
        self._ready = False
        self._simulated = None

    def _deadline(self, deadline):
        if isinstance(deadline,bool) or not isinstance(deadline,(int,float)) or not math.isfinite(deadline):
            raise ValueError('absolute deadline must be finite')
        if self.clock() >= deadline:
            raise BackendTimeoutError('navigator deadline expired')

    def _call(self, name, *args):
        self._deadline(args[-1])
        if not self._ready or self.driver is None:
            raise NotConfiguredError('NOT_CONFIGURED: navigator transport has no verified driver')
        result = getattr(self.driver,name)(*args)
        self._deadline(args[-1])
        return result

    def _capabilities(self, caps):
        if not isinstance(caps,Capabilities):
            raise BackendProtocolError('invalid navigator capabilities')
        caps.validate()
        if self._simulated is not None and self._simulated != caps.simulated:
            raise BackendProtocolError('navigator evidence kind changed')
        self._simulated = caps.simulated
        return caps

    def hello(self, deadline):
        self._deadline(deadline)
        if not isinstance(self.driver,Transport):
            raise NotConfiguredError('NOT_CONFIGURED: physical Transport driver is pending')
        # Mock tests explicitly use a mock profile. It can only advertise simulated.
        if self.profile.get('status') == 'mock':
            caps = self._capabilities(self.driver.hello(deadline))
            if not caps.simulated:
                raise BackendProtocolError('mock profile cannot advertise hardware measurements')
            self._deadline(deadline)
            self._ready = True
            return caps
        validate_overlay(self.profile,self.overlay)
        self._ready = True
        try:
            caps = self._capabilities(self._call('hello',deadline))
            if caps.simulated:
                raise BackendProtocolError('configured hardware driver advertised simulation')
            if caps.firmware_id != self.profile['firmware_id']:
                raise BackendProtocolError('running firmware identity differs from release manifest')
            return caps
        except Exception:
            self._ready = False
            raise

    def submit(self, packet, deadline):
        if not isinstance(packet,bytes):
            raise TypeError('mailbox packet must be immutable bytes')
        return self._call('submit',packet,deadline)

    def poll(self, deadline):
        return self._call('poll',deadline)

    def ack(self, epoch, request_id, deadline):
        return self._call('ack',epoch,request_id,deadline)

    def reset(self, deadline):
        return self._capabilities(self._call('reset',deadline))


def create_host(profile_path, mode='ise', *, driver=None, overlay=None, timeout_s=5.0):
    transport = NavigatorTransport(read_profile(profile_path),driver=driver,overlay=overlay)
    return AsconHost(MailboxBackend(transport,mode=mode,timeout_s=timeout_s))
