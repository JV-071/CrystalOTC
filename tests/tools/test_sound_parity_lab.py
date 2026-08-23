#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("sound_parity_lab", ROOT / "tools/sound_parity_lab.py")
assert SPEC and SPEC.loader
LAB = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(LAB)


class SoundParityLabTests(unittest.TestCase):
    def test_relative_fingerprint_survives_uniform_pitch_shift(self) -> None:
        original = [(5, 8), (6, 9), (7, 8), (8, 10), (7, 9), (6, 8)]
        shifted = [(primary + 3, secondary + 3) for primary, secondary in original]
        original_keys = {kind: key for kind, key, _ in LAB.shingle_keys(original)}
        shifted_keys = {kind: key for kind, key, _ in LAB.shingle_keys(shifted)}

        self.assertNotEqual(original_keys["absolute"], shifted_keys["absolute"])
        self.assertEqual(original_keys["relative"], shifted_keys["relative"])

    def test_tiny_tail_overlap_is_not_a_complete_match(self) -> None:
        self.assertFalse(LAB.has_substantial_overlap(asset_frames=2509, capture_frames=300, overlap=11))
        self.assertTrue(LAB.has_substantial_overlap(asset_frames=2509, capture_frames=300, overlap=300))

    def test_audible_onset_uses_first_frame_above_threshold_after_command(self) -> None:
        envelope = [(1.00, -20.0), (2.00, -80.0), (2.01, -58.0), (2.02, -30.0)]

        onset = LAB.first_audible_frame(envelope, start_seconds=2.0, end_seconds=2.5, threshold_db=-60.0)

        self.assertEqual(onset, (2.01, -58.0))

    def test_sequence_comparison_reports_missing_extra_and_relative_timing(self) -> None:
        official = [
            {"audio_file_id": 10, "time_us": 1_000_000},
            {"audio_file_id": 20, "time_us": 1_200_000},
            {"audio_file_id": 30, "time_us": 1_500_000},
        ]
        crystal = [
            {"audio_file_id": 10, "time_us": 9_000_000},
            {"audio_file_id": 99, "time_us": 9_050_000},
            {"audio_file_id": 30, "time_us": 9_540_000},
        ]

        result = LAB.sequence_comparison(official, crystal)

        self.assertEqual(result["matched"], 2)
        self.assertEqual([item["audio_file_id"] for item in result["missing"]], [20])
        self.assertEqual([item["audio_file_id"] for item in result["extra"]], [99])
        self.assertEqual(result["timing"][-1]["timing_delta_ms"], 40.0)

    def test_delivery_comparison_requires_id_role_and_world_position(self) -> None:
        server = [
            {
                "effect_id": 42,
                "time_us": 2_000_000,
                "world": {"x": 100, "y": 101, "z": 7},
                "role": "main",
            }
        ]
        client = [
            {
                "effect_id": 42,
                "time_us": 2_012_000,
                "world": {"x": 100, "y": 101, "z": 7},
                "role": "main",
            }
        ]

        result = LAB.delivery_comparison(server, client, window_ms=100)

        self.assertEqual(result["matched"], 1)
        self.assertEqual(result["latencies"][0]["latency_ms"], 12.0)

    def test_delivery_comparison_includes_anthem_packets(self) -> None:
        server = [{"packet_kind": "anthem", "anthem_kind": "music", "id": 7, "time_us": 1_000_000}]
        client = [{"packet_kind": "anthem", "anthem_kind": "music", "id": 7, "time_us": 1_008_000}]

        result = LAB.delivery_comparison(server, client, window_ms=100)

        self.assertEqual(result["matched"], 1)
        self.assertEqual(result["latencies"][0]["packet_kind"], "anthem")
        self.assertEqual(result["latencies"][0]["latency_ms"], 8.0)

    def test_scheduler_summary_counts_rejection_reasons(self) -> None:
        events = [
            {"event": "packet.sound_effect"},
            {"event": "effect.request"},
            {"event": "effect.drop", "data": {"reason": "duplicate_throttle"}},
            {"event": "effect.drop", "data": {"reason": "duplicate_throttle"}},
        ]

        result = LAB.scheduler_summary(events)

        self.assertEqual(result["sound_packets_received"], 1)
        self.assertEqual(result["families"]["effect"]["drops"], 2)
        self.assertEqual(result["families"]["effect"]["drop_reasons"]["duplicate_throttle"], 2)

    def test_tcpdump_line_is_converted_to_epoch_microseconds(self) -> None:
        packet = LAB.parse_tcpdump_line(
            "1787509344.123456 IP 127.0.0.1.7171 > 127.0.0.1.55555: Flags [P.], length 42"
        )

        self.assertIsNotNone(packet)
        self.assertEqual(packet["epoch_us"], 1_787_509_344_123_456)
        self.assertEqual(packet["length"], 42)


if __name__ == "__main__":
    unittest.main()
