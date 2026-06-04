# Copyright (c) 2026 Mounith Reddy
# SPDX-License-Identifier: Apache-2.0
"""Tests for the AI-accelerator PPA scorecard calculator."""

import math

import pytest

from ppa_scorecard import ppa_metrics


def test_known_values_n16_int8():
    # N=16 weight-stationary MVM: 256 MACs/cycle. At 100 MHz, 5 mW, 1.32 mm^2.
    m = ppa_metrics(n=16, f_hz=100e6, power_w=5e-3, die_area_mm2=1.32)

    assert m["macs_per_cycle"] == 256
    assert math.isclose(m["macs_per_s"], 2.56e10, rel_tol=1e-12)
    # 1 MAC = 2 OPS by convention -> peak 0.0512 TOPS
    assert math.isclose(m["peak_tops"], 0.0512, rel_tol=1e-9)
    assert math.isclose(m["tops_per_w"], 10.24, rel_tol=1e-9)
    assert math.isclose(m["tops_per_mm2"], 0.0512 / 1.32, rel_tol=1e-9)
    assert math.isclose(m["pj_per_mac"], 0.1953125, rel_tol=1e-9)


def test_ops_per_mac_one_halves_tops():
    # Counting MACs (not 2*MAC ops) should halve the reported TOPS.
    m = ppa_metrics(n=16, f_hz=100e6, power_w=5e-3, die_area_mm2=1.32, ops_per_mac=1)
    assert math.isclose(m["peak_tops"], 0.0256, rel_tol=1e-9)


def test_streaming_lane_uses_explicit_macs_per_cycle():
    # Serialized weight-streaming design: 4-wide lane, not N*N parallel.
    s = ppa_metrics(n=16, f_hz=100e6, power_w=8e-3, die_area_mm2=0.5, macs_per_cycle=4)
    assert s["macs_per_cycle"] == 4
    assert math.isclose(s["macs_per_s"], 4e8, rel_tol=1e-12)
    assert math.isclose(s["pj_per_mac"], 20.0, rel_tol=1e-9)
    assert math.isclose(s["peak_tops"], 0.0008, rel_tol=1e-9)


def test_invalid_macs_per_cycle_raises():
    with pytest.raises(ValueError):
        ppa_metrics(n=16, f_hz=100e6, power_w=8e-3, die_area_mm2=0.5, macs_per_cycle=0)


def test_scaling_n_is_quadratic_in_macs():
    m4 = ppa_metrics(n=4, f_hz=100e6, power_w=5e-3, die_area_mm2=1.0)
    m8 = ppa_metrics(n=8, f_hz=100e6, power_w=5e-3, die_area_mm2=1.0)
    assert m4["macs_per_cycle"] == 16
    assert m8["macs_per_cycle"] == 64  # 4x for 2x N


@pytest.mark.parametrize(
    "kwargs",
    [
        dict(n=0, f_hz=100e6, power_w=5e-3, die_area_mm2=1.0),
        dict(n=16, f_hz=0, power_w=5e-3, die_area_mm2=1.0),
        dict(n=16, f_hz=100e6, power_w=0.0, die_area_mm2=1.0),
        dict(n=16, f_hz=100e6, power_w=5e-3, die_area_mm2=0.0),
        dict(n=16, f_hz=100e6, power_w=-1.0, die_area_mm2=1.0),
    ],
)
def test_invalid_inputs_raise(kwargs):
    with pytest.raises(ValueError):
        ppa_metrics(**kwargs)
