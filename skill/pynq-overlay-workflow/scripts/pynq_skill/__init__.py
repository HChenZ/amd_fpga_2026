"""Board-agnostic PYNQ host helpers (overlay checks, register contracts, bounded DMA,
golden comparison, report collection). Standard library only; `pynq` is optional."""

__version__ = '0.1.0'


class PynqSkillError(RuntimeError):
    """Base class: every check failure carries a list of human-readable problems."""

    def __init__(self, message, problems=None):
        self.problems = list(problems or [])
        if self.problems:
            message = message + ':\n  - ' + '\n  - '.join(self.problems)
        super().__init__(message)
