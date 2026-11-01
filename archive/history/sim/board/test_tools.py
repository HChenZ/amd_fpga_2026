import sys
from pathlib import Path
import tempfile
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parent))
from coe import BRAM_BYTES, convert, image_words, parse_coe
from uart_log import parse
from run_tests import aggregate


class ImageTests(unittest.TestCase):
    def test_endian_partial_word_and_padding(self):
        with tempfile.TemporaryDirectory() as folder:
            d = Path(folder)
            data = bytes.fromhex('78563412aabbccdd01')
            (d/'a.bin').write_bytes(data)
            words = image_words(data)
            (d/'a.hex').write_text('\n'.join(f'{word:08x}' for word in words))
            result = convert(d/'a.bin',d/'a.hex',d/'a.coe')
            self.assertEqual(result['words'],32768)
            self.assertEqual(parse_coe((d/'a.coe').read_text())[:4],[0x12345678,0xddccbbaa,1,0])
            (d/'a.hex').write_text('78563412\n')
            with self.assertRaises(ValueError):
                convert(d/'a.bin',d/'a.hex',d/'bad.coe')

    def test_overflow_empty_and_exact_capacity(self):
        for data in (b'',bytes(BRAM_BYTES+1)):
            with self.assertRaises(ValueError):
                image_words(data)
        self.assertEqual(len(image_words(bytes(BRAM_BYTES))),32768)

    def test_invalid_coe(self):
        for text in ('memory_initialization_radix=2; memory_initialization_vector=00000000;',
                     'memory_initialization_radix=16; memory_initialization_vector=00000000,;',
                     'memory_initialization_radix=16; memory_initialization_vector=000000000;'):
            with self.assertRaises(ValueError):
                parse_coe(text)


class LogTests(unittest.TestCase):
    def test_structured_simulation_and_identity(self):
        result = parse('[ASCON] mode=ISE firmware_version=v1 rtl_sha='+'a'*40+' bitstream_sha='+'b'*64+
                       '\n[ASCON] test=kat status=PASS mcycle=4294967297')
        row = result['records'][0]
        self.assertEqual((row['mode'],row['firmware_version'],row['mcycle']),('ise','v1',4294967297))
        self.assertTrue(row['simulated'])
        self.assertEqual(result['status'],'PASS')

    def test_legacy_log_missing_identity(self):
        result = parse('=== ASCON-AEAD128 software on RV32IM ===\nKAT empty : PASS\nenc 16B : 123 cycles, 1 inst')
        self.assertEqual(result['records'][0]['mode'],'sw')
        self.assertIsNone(result['records'][0]['bitstream_sha'])
        self.assertEqual(result['records'][1]['status'],'NOT_RUN')

    def test_failure_dominates_summary_and_invalid_cycles(self):
        self.assertEqual(parse('KAT empty : FAIL\nKAT: 6/6 PASS')['status'],'FAIL')
        self.assertEqual(parse('[ASCON] test=bad status=PASS mcycle=-1')['status'],'FAIL')
        self.assertEqual(parse('[ASCON] test=bad status=PASS mcycle=18446744073709551616')['status'],'FAIL')
        self.assertEqual(parse('noise only')['status'],'BLOCKED')
        self.assertEqual(parse('[ASCON] test=x status=FAIL status=PASS')['status'],'FAIL')
        self.assertEqual(parse('[ASCON] status=FAIL')['status'],'FAIL')

    def test_real_firmware_log_shapes_keep_cycle_scopes_separate(self):
        hw = parse('=== ASCON-AEAD128 hardware (MMIO) on RV32IM ===\ndec roundtrip: PASS\n'
                   'crypto latency : 100 cycles\nfull MMIO : 664 cycles','rtl_simulation')
        self.assertEqual(hw['records'][0]['mode'],'hw')
        self.assertIsNone(hw['records'][1]['mcycle'])
        self.assertEqual(hw['records'][1]['crypto_core_cycles'],100)
        self.assertEqual(hw['records'][2]['mcycle'],664)
        ise = parse('=== ASCON-AEAD128 ISE (permutation in hardware) ===\nISE cycles : 2559','rtl_simulation')
        self.assertEqual(ise['records'][0]['mcycle'],2559)

    def test_aggregation_never_masks_blocker(self):
        self.assertEqual(aggregate(['PASS','BLOCKED']),'BLOCKED')
        self.assertEqual(aggregate(['PASS','FAIL','BLOCKED']),'FAIL')
        self.assertEqual(aggregate(['NOT_RUN']),'NOT_RUN')


if __name__ == '__main__':
    unittest.main()
