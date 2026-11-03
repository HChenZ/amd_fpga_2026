"""Check actual generated HWH against the implemented driver/ABI (no board access)."""
from pathlib import Path
import argparse,hashlib,json,sys,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from src.pynq.dma_transport import dma_configuration

def main():
 p=argparse.ArgumentParser();p.add_argument('hwh',type=Path);p.add_argument('--output',required=True,type=Path);a=p.parse_args()
 tree=ET.parse(a.hwh);modules={m.attrib['INSTANCE']:m for m in tree.findall('.//MODULE')}
 assert modules['dma'].attrib['MODTYPE']=='axi_dma'
 assert modules['engine'].attrib['MODTYPE']=='dma_direct_top'
 parameters={n.attrib['NAME']:n.attrib['VALUE'] for n in modules['dma'].findall('./PARAMETERS/PARAMETER')}
 config=dma_configuration(parameters)
 assert config=={'max_transfer':16383,'tx_alignment':4,'rx_alignment':4},config
 core={n.attrib['NAME']:n.attrib['VALUE'] for n in modules['engine'].findall('./PARAMETERS/PARAMETER')}
 assert int(core['MAX_BYTES'])==1024
 ps={n.attrib['NAME']:n.attrib['VALUE'] for n in modules['ps7'].findall('./PARAMETERS/PARAMETER')}
 reset={n.attrib['NAME']:n.attrib['VALUE'] for n in modules['reset'].findall('./PARAMETERS/PARAMETER')}
 assert ps['PCW_USE_S_AXI_HP0']=='1' and ps['PCW_USE_M_AXI_GP0']=='1'
 assert int(ps['PCW_S_AXI_HP0_DATA_WIDTH'])==64 and float(ps['PCW_FPGA0_PERIPHERAL_FREQMHZ'])==100
 assert reset['C_EXT_RESET_HIGH']=='0', 'active-low FCLK_RESET0_N polarity mismatch'
 ranges={n.attrib['INSTANCE']:n.attrib for n in modules['ps7'].findall('./MEMORYMAP/MEMRANGE')}
 if not ranges:ranges={n.attrib['INSTANCE']:n.attrib for n in modules['ps7'].findall('.//MEMRANGE')}
 assert int(ranges['engine']['BASEVALUE'],16)==0x40000000
 assert int(ranges['dma']['BASEVALUE'],16)==0x40400000
 result={'status':'PASS','kind':'static_hwh_driver_contract','board':'NOT_RUN',
         'hwh_sha256':hashlib.sha256(a.hwh.read_bytes()).hexdigest(),'dma_configuration':config,
         'max_ad_bytes':1024,'max_message_bytes':1024,'address_ranges':ranges,
         'hp0_width':64,'fclk_config_mhz':100,'external_reset_active_low':True}
 a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(result,indent=2),encoding='utf-8')
 print('PASS actual HWH / PYNQ2.7 adapter configuration',a.output)
if __name__=='__main__':main()
