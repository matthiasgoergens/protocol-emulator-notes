from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import emu_runner


def trace_entry(value: int = 0) -> bytes:
    return bytes([0] * 5 + [value] + [0] * 12)


class ControlSelectionTest(unittest.TestCase):
    def test_uses_unfiltered_uart_loop_and_selected_subslot(self) -> None:
        excluded = {"name": "excluded", "imem": [], "subslot": False}
        generic = {"name": "uart_loop", "imem": [0x3002], "subslot": False}
        ineligible = {"name": "subslot_no_q1", "imem": [0x1000], "subslot": True}
        eligible = {"name": "subslot_selected", "imem": [0x1001], "subslot": True}

        plan = emu_runner.negative_controls(
            [excluded, generic, ineligible, eligible], [ineligible, eligible]
        )

        self.assertEqual(
            [(test["name"], mutate) for test, mutate in plan],
            [
                ("uart_loop", "trace"),
                ("uart_loop", "imem"),
                ("subslot_selected", "q"),
                ("subslot_selected", "swap"),
            ],
        )
        self.assertEqual(generic["imem"], [0x3002])

    def test_requires_uart_loop_for_generic_controls(self) -> None:
        with self.assertRaisesRegex(emu_runner.ControlSetupError, "require uart_loop"):
            emu_runner.negative_controls([{"name": "other", "imem": [], "subslot": False}], [])

    def test_missing_mutation_instructions_are_control_setup_errors(self) -> None:
        with self.assertRaisesRegex(emu_runner.ControlSetupError, "LDD with n > 1"):
            emu_runner.mutate_imem([0x3000], "imem")
        with self.assertRaisesRegex(emu_runner.ControlSetupError, "SETP with q = 1"):
            emu_runner.mutate_imem([0x1000], "q")

    def test_short_trace_and_unswappable_trace_are_control_setup_errors(self) -> None:
        with self.assertRaisesRegex(emu_runner.ControlSetupError, "only 4 trace entries"):
            emu_runner.mutate_trace([trace_entry()] * 4, "trace")
        with self.assertRaisesRegex(emu_runner.ControlSetupError, "no pin_sub nibble"):
            emu_runner.mutate_trace([trace_entry()], "swap")

    def test_trace_mutations_change_the_intended_fields(self) -> None:
        trace = [trace_entry()] * 5
        mutated_trace = emu_runner.mutate_trace(trace, "trace")
        self.assertEqual(mutated_trace[2][5], 1)

        entry = bytearray(trace_entry())
        entry[13] = 0x02
        mutated_quarters = emu_runner.mutate_trace([bytes(entry)], "swap")
        self.assertEqual(mutated_quarters[0][13], 0x04)


if __name__ == "__main__":
    unittest.main()
