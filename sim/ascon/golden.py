"""Read frozen AEAD expectations or call the locked C permutation reference."""
import argparse
import json
from support import DATA, backend, parse_kat, verify_sources


class GoldenModel:
    def __init__(self, cc="gcc"):
        verify_sources()
        self.reference = backend("upstream-c", cc)

    def permutation(self, state_bus, rounds, constant=0):
        if len(state_bus) != 80:
            raise ValueError("state_bus must be 80 hex digits: {s4,s3,s2,s1,s0}")
        value = int(state_bus, 16)
        state = [(value >> (64*i)) & ((1 << 64) - 1) for i in range(5)]
        out = self.reference.permute(state, rounds, constant)
        return dict(expected_words=[f"{w:016x}" for w in out],
                    expected_bus="".join(f"{w:016x}" for w in reversed(out)),
                    expected_bytes=b"".join(w.to_bytes(8, "little") for w in out).hex())


def aead_case(case_id):
    verify_sources()
    cases = parse_kat() + json.loads((DATA / "aead_cases.json").read_text())["cases"]
    for row in cases:
        if row["id"] == case_id:
            return row
    raise ValueError(f"Unknown case: {case_id}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("round", "p8", "p12", "aead"))
    parser.add_argument("--state-bus")
    parser.add_argument("--constant", type=lambda s: int(s, 16), default=0x4B)
    parser.add_argument("--case")
    parser.add_argument("--cc", default="gcc")
    parser.add_argument("--format", choices=("json", "hex"), default="json")
    args = parser.parse_args()
    try:
        if args.operation == "aead":
            result = aead_case(args.case)
            compact = result["ciphertext"] + result["tag"]
        else:
            rounds = {"round": 1, "p8": 8, "p12": 12}[args.operation]
            result = GoldenModel(args.cc).permutation(args.state_bus or "", rounds, args.constant)
            compact = result["expected_bus"]
        print(compact if args.format == "hex" else json.dumps(result, indent=2))
        return 0
    except Exception as exc:
        print(f"FAIL golden {type(exc).__name__}: {exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
