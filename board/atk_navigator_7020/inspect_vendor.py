"""Read selected vendor files/ZIP members without opening/upgrading Vivado projects."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import zipfile
import re

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'sim/board'))
from common import local_output, sha256, write_json

GUIDE = '2_文档教程/5_【正点原子】领航者ZYNQ之PYNQ开发指南_V3.2.pdf'
BASE_PDF = '3_开发板原理图和硬件相关文件/领航者ZYNQ底板原理图_V3.9.pdf'
CORE_PDF = '3_开发板原理图和硬件相关文件/ZYNQ7010_7020核心板原理图_2V5.pdf'
XDC = '3_开发板原理图和硬件相关文件/NAVIGATOR_ZYNQ_IO.xdc'
ZIP = '4_Source_Code/5_PYNQ_Design/ZYNQ_7020_PYNQ.zip'
MEMBERS = ('base/base.srcs/sources_1/bd/base/base.bd',
           '2_axi_gpio/vivado/axi_gpio/axi_gpio.srcs/sources_1/bd/system/system.bd',
           '2_axi_gpio/vivado/axi_gpio/axi_gpio.xpr', '3_mmio/notebook/mmio.ipynb')
PARAMS = ('PCW_UIPARAM_DDR_PARTNO','PCW_UIPARAM_DDR_MEMORY_TYPE','PCW_UIPARAM_DDR_BUS_WIDTH',
          'PCW_UIPARAM_DDR_FREQ_MHZ','PCW_UIPARAM_ACT_DDR_FREQ_MHZ',
          'PCW_DDR_RAM_BASEADDR','PCW_DDR_RAM_HIGHADDR','PCW_UART0_PERIPHERAL_ENABLE',
          'PCW_UART0_UART0_IO','PCW_UART0_BAUD_RATE','PCW_UART1_PERIPHERAL_ENABLE',
          'PCW_SD0_PERIPHERAL_ENABLE','PCW_SD0_SD0_IO','PCW_SD0_GRP_CD_IO',
          'PCW_ENET0_PERIPHERAL_ENABLE','PCW_ENET0_ENET0_IO','PCW_ENET0_GRP_MDIO_IO',
          'PCW_CRYSTAL_PERIPHERAL_FREQMHZ','PCW_ACT_FPGA0_PERIPHERAL_FREQMHZ',
          'PCW_ACT_FPGA1_PERIPHERAL_FREQMHZ','PCW_ACT_FPGA2_PERIPHERAL_FREQMHZ',
          'PCW_ACT_FPGA3_PERIPHERAL_FREQMHZ','PCW_EN_RST0_PORT')


def ps7_components(value):
    if isinstance(value,dict):
        if 'processing_system7' in value.get('vlnv','') and 'xci_name' in value:
            yield value
        for child in value.values():
            yield from ps7_components(child)
    elif isinstance(value,list):
        for child in value:
            yield from ps7_components(child)


def inspect(root, out):
    root, out = Path(root), local_output(out)
    out.mkdir(parents=True,exist_ok=False)
    report = dict(task_id='B03/Y01 navigator_preboard',owner='TBD',status='PASS',
                  evidence_kind='vendor_static_inspection',vendor_root=str(root),files={},members={})
    for relative in (GUIDE,BASE_PDF,CORE_PDF,XDC):
        path = root/relative
        report['files'][relative] = dict(bytes=path.stat().st_size,sha256=sha256(path))
    pin_pattern = r'PACKAGE_PIN\s+(\w+)\s+IOSTANDARD\s+(\w+)\s*\}\s*\[get_ports\s+\{?([^\}\s]+)\}?\]'
    official = re.findall(pin_pattern,(root/XDC).read_text(encoding='gb18030',errors='replace'))
    candidate = re.findall(pin_pattern,(Path(__file__).with_name('navigator_uart.xdc')).read_text())
    renames = {'clk':'sys_clk','reset_btn':'sys_rst_n','button[0]':'key[0]','button[1]':'key[1]'}
    if len(candidate)!=8 or len({x[2] for x in candidate})!=8 or len({x[0] for x in candidate})!=8:
        raise ValueError('candidate XDC has missing/duplicate ports or pins')
    report['pin_mapping'] = []
    for pin,standard,port in candidate:
        vendor_port = renames.get(port,port)
        if (pin,standard,vendor_port) not in official:
            raise ValueError('candidate pin not supported by vendor XDC: '+port)
        report['pin_mapping'].append(dict(port=port,vendor_port=vendor_port,pin=pin,iostandard=standard))
    report['xdc_status'] = 'PASS_STATIC_ONLY'
    with zipfile.ZipFile(root/ZIP) as archive:
        report['archive'] = dict(path=ZIP,bytes=(root/ZIP).stat().st_size,
                                 member_count=len(archive.infolist()),sha256=sha256(root/ZIP))
        for name in MEMBERS:
            data = archive.read(name)
            item = dict(sha256=hashlib.sha256(data).hexdigest(),bytes=len(data))
            if name.endswith('.bd'):
                design = json.loads(data)['design']
                item['design_info'] = design['design_info']
                item['ps7'] = [dict(vlnv=comp['vlnv'],parameters={k:comp['parameters'][k]['value']
                    for k in PARAMS if k in comp['parameters']}) for comp in ps7_components(design)]
                item['reset_clock_nets'] = {k:v for k,v in design.get('nets',{}).items()
                    if 'FCLK' in k or k.endswith(('peripheral_aresetn','interconnect_aresetn'))}
            elif name.endswith('.xpr'):
                item['version_part_lines'] = [l.strip() for l in data.decode().splitlines()
                    if 'Product Version:' in l or 'Name="Part"' in l]
            else:
                item['code_cells'] = [''.join(c['source']) for c in json.loads(data)['cells'] if c['cell_type']=='code']
            report['members'][name] = item
        report['archive_images'] = [n for n in archive.namelist() if n.lower().endswith(('.img','.img.zip','.img.xz'))]
    # Names only; do not extract/copy other examples or large archives.
    report['local_image_candidates'] = [str(p.relative_to(root)) for p in root.rglob('*')
        if p.is_file() and ('.img' in p.name.lower() or '2.7.0' in p.name)]
    for name, relative in (('guide',GUIDE),('base_schematic',BASE_PDF),('core_schematic',CORE_PDF)):
        command = ['pdftotext','-layout',str(root/relative),str(out/(name+'.txt'))]
        r = subprocess.run(command,capture_output=True)
        report.setdefault('commands',[]).append(dict(command=command,exit_code=r.returncode,
            stderr=r.stderr.decode('utf-8','replace')))
        if r.returncode:
            report['status']='FAIL'
    write_json(out/'vendor_inventory.json',report)
    print(report['status'],out/'vendor_inventory.json')
    return 0 if report['status']=='PASS' else 1


if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--vendor-root',type=Path,required=True)
    p.add_argument('--out',type=Path,required=True)
    args=p.parse_args()
    sys.exit(inspect(args.vendor_root,args.out))
