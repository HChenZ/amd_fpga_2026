import numpy as np
from pynq import allocate


def transform(overlay, data, timeout_s=1.0):
    dma = overlay.axi_dma_0
    inbuf = allocate(shape=(len(data),), dtype=np.uint8)
    outbuf = allocate(shape=(len(data),), dtype=np.uint8)
    inbuf[:] = np.frombuffer(data, dtype=np.uint8)
    dma.sendchannel.transfer(inbuf)
    dma.recvchannel.transfer(outbuf)
    dma.sendchannel.wait()
    dma.recvchannel.wait()
    return bytes(outbuf)
