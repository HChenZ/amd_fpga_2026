# Experimental multiblock Ascon DMA path

Independent from the released 16-byte core. `ascon_aead_multiblock` uses the existing
Final round function, byte input memories and private candidate output storage.
`ascon_axis_direct` implements D01Q/D01R v2, mode 4 only, bounded packets and response
backpressure. Output plaintext is not readable until authentication succeeds.
No board acceptance is implied; see data/advanced/dma_direct for actual regression evidence.
