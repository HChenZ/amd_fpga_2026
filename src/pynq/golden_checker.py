"""Full locked KAT checker. Expected bytes come from the official corpus only."""
import argparse
import sys

if __package__:
    from .ascon_host_api import (AsconHost, AuthenticationError,
                                KAT_PATH, KAT_SHA256, checked_bytes, load_python)
else:
    from ascon_host_api import (AsconHost, AuthenticationError,
                               KAT_PATH, KAT_SHA256, checked_bytes, load_python)


def parse_kat():
    cases = []
    text = checked_bytes(KAT_PATH, KAT_SHA256).decode("ascii")
    for block in text.strip().split("\n\n"):
        row = dict(line.split(" =", 1) for line in block.splitlines())
        case = {name: bytes.fromhex(row[name].strip())
                for name in ("Key", "Nonce", "PT", "AD", "CT")}
        case["count"] = int(row["Count"])
        if len(case["CT"]) != len(case["PT"]) + 16:
            raise ValueError("invalid KAT output length")
        cases.append(case)
    if ([c["count"] for c in cases] != list(range(1, 1090))
            or {(len(c["PT"]), len(c["AD"])) for c in cases}
            != {(m, a) for m in range(33) for a in range(33)}):
        raise ValueError("incomplete KAT corpus")
    return cases


def first_difference(expected, actual):
    for offset in range(max(len(expected), len(actual))):
        e = f"{expected[offset]:02x}" if offset < len(expected) else "<end>"
        a = f"{actual[offset]:02x}" if offset < len(actual) else "<end>"
        if e != a:
            return f"byte={offset} expected={e} actual={a} (zero-based)"
    return None


def check_all(host=None, *, inject=None):
    host = host if host is not None else AsconHost()
    # The task card's ascon/python path is actually ascon/pyascon.
    repository = load_python("ascon/pyascon/ascon.py")
    passed = failed = rejected = 0
    for c in parse_kat():
        k, n, ad, pt, expected = (c[f] for f in ("Key", "Nonce", "AD", "PT", "CT"))
        try:
            encrypted = host.encrypt(k, n, ad, pt)
            actual = encrypted.ciphertext + encrypted.tag
            if inject and c["count"] == (34 if inject == "ciphertext" else 1):
                offset = 0 if inject == "ciphertext" else len(actual) - 16
                actual = actual[:offset] + bytes([actual[offset] ^ 1]) + actual[offset+1:]
            comparisons = (
                ("api/encrypt CT||tag", expected, actual),
                ("repository/encrypt CT||tag", expected,
                 repository.ascon_encrypt(k, n, ad, pt, "Ascon-AEAD128")),
                ("api/decrypt", pt, host.decrypt(k, n, ad, expected[:-16], expected[-16:]).plaintext),
                ("repository/decrypt", pt,
                 repository.ascon_decrypt(k, n, ad, expected, "Ascon-AEAD128")))
            for label, answer, value in comparisons:
                if not isinstance(value, bytes):
                    raise AssertionError(label + " did not return bytes")
                detail = first_difference(answer, value)
                if detail:
                    raise AssertionError(label + " " + detail)
            # Authenticate official expected input, not the API's own encryption.
            positions = [len(expected) - 16, len(expected) - 1]
            if pt:
                positions += [0, len(pt) - 1]
            for offset in positions:
                bad = expected[:offset] + bytes([expected[offset] ^ 1]) + expected[offset+1:]
                try:
                    host.decrypt(k, n, ad, bad[:-16], bad[-16:])
                except AuthenticationError:
                    rejected += 1
                else:
                    raise AssertionError(f"tamper accepted byte={offset} (zero-based)")
            passed += 1
        except Exception as exc:
            failed += 1
            print(f"FAIL kat_{c['count']:04d} {type(exc).__name__}: {exc}")
    print(f"KAT PASS {passed} / FAIL {failed}")
    print(f"TAMPER REJECT {rejected}; cycle provenance is reported by the API; no board measurements collected")
    return {"passed": passed, "failed": failed, "rejected": rejected}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inject", choices=("tag", "ciphertext"),
                        help="corrupt one observed output; must exit 1")
    parser.add_argument("--backend", choices=("reference", "mailbox"), default="reference",
                        help="mailbox uses the draft in-memory peer, not a board")
    parser.add_argument("--mode", choices=("sw", "hw", "ise"), default="ise")
    args = parser.parse_args(argv)
    try:
        if args.backend == "mailbox":
            if __package__:
                from .mailbox_backend import MailboxBackend, MemoryTransport
            else:
                from mailbox_backend import MailboxBackend, MemoryTransport
            host = AsconHost(MailboxBackend(MemoryTransport(polls_to_complete=0), args.mode))
        else:
            if __package__:
                from .ascon_host_api import SimulatedBackend
            else:
                from ascon_host_api import SimulatedBackend
            host = AsconHost(SimulatedBackend(args.mode))
        print(f"BACKEND {host.backend.name}; simulated={host.backend.simulated}")
        return int(check_all(host, inject=args.inject)["failed"] != 0)
    except Exception as exc:
        print(f"FAIL setup {type(exc).__name__}: {exc}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
