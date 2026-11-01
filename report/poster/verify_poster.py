"""Check the poster against the locked repository evidence (stdlib only)."""
import hashlib
import json
import statistics
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
NS = {"p": "http://schemas.openxmlformats.org/presentationml/2006/main",
      "a": "http://schemas.openxmlformats.org/drawingml/2006/main"}


def main():
    benchmark_path = ROOT / "data/pynq/notebook_20261031_112052/pynq_warm_benchmark.json"
    benchmark = json.loads(benchmark_path.read_text(encoding="utf-8-sig"))
    kat = json.loads((benchmark_path.parent / "pynq_board_smoke.json").read_text(encoding="utf-8-sig"))
    gate = json.loads((ROOT / "data/pynq/error_gate_20261031_112812/pynq_board_error_gate.json").read_text(encoding="utf-8-sig"))
    checks = []

    def check(name, value):
        if not value:
            raise ValueError(name)
        checks.append(name)

    check("real_board", benchmark["service"]["simulated"] is False)
    check("benchmark_conditions", (benchmark["kat"], benchmark["plaintext_bytes"], benchmark["ad_bytes"], benchmark["warmup"], benchmark["repetitions"]) == (529, 16, 0, 5, 30))
    for mode in ("sw", "hw", "ise"):
        check(f"{mode}_kat_and_tag", kat["modes"][mode]["kat_pass"] == kat["modes"][mode]["tag_reject"] == 289)
        for operation in ("encrypt", "decrypt"):
            row = benchmark["modes"][mode][operation]
            check(f"{mode}_{operation}_raw_median", len(row["raw_cycles"]) == 30 and statistics.median(row["raw_cycles"]) == row["summary"]["median"])
    check("error_recovery", len(gate["checks"]) == 9 and all(c["status"] == "PASS" for c in gate["checks"]) and gate["reset_count"] == 7)
    with zipfile.ZipFile(HERE / "ascon_soc_poster.pptx") as package:
        check("zip_crc", package.testzip() is None)
        pres = ET.fromstring(package.read("ppt/presentation.xml"))
        check("one_slide", len(pres.find("p:sldIdLst", NS)) == 1)
        check("template_dimensions", pres.find("p:sldSz", NS).attrib["cx"] == "12192000" and pres.find("p:sldSz", NS).attrib["cy"] == "6858000")
        slide = ET.fromstring(package.read("ppt/slides/slide1.xml"))
        text = "\n".join("".join(t.text or "" for t in p.findall(".//a:t", NS)) for p in slide.findall(".//a:p", NS))
        check("confirmed_team", all(s in text for s in ("熊雅琦", "胡潇正", "黄晨中", "华南理工大学")))
        check("sample_content_removed", all(s not in text for s in ("Hao Zhang", "Radio telescopes", "待补充", "Title ：", "指导老师")))
        check("measurement_boundary", "周期不含 PS/UART" in text and "跨上电稳定性未测" in text)
        for mode in ("sw", "hw", "ise"):
            for operation in ("encrypt", "decrypt"):
                value = benchmark["modes"][mode][operation]["summary"]["median"]
                check(f"{mode}_{operation}_printed", f"{value:,.0f}" in text)
        check("editable_table", len(slide.findall(".//a:tbl", NS)) == 1)
        for mode in ("hw", "ise"):
            for operation in ("encrypt", "decrypt"):
                sw = benchmark["modes"]["sw"][operation]["summary"]["median"]
                accelerated = benchmark["modes"][mode][operation]["summary"]["median"]
                check(f"{mode}_{operation}_speedup", f"{sw/accelerated:.3f}×" in text)
        notes = package.read("ppt/notesSlides/notesSlide1.xml").decode("utf-8")
        check("source_notes", benchmark_path.name in notes and "40_summary.json" in notes)
    fit = json.loads((HERE / "text_fit.json").read_text(encoding="utf-8-sig"))
    check("powerpoint_text_fit", fit["overflow_count"] == 0)
    result = {"status": "PASS", "checks": checks, "check_count": len(checks), "pptx_sha256": hashlib.sha256((HERE / "ascon_soc_poster.pptx").read_bytes()).hexdigest()}
    (HERE / "verification.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"PASS: {len(checks)} checks")


if __name__ == "__main__":
    main()
