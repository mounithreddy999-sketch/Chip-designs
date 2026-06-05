#!/usr/bin/env python3
"""
M11: EACB (error-aware / offset-aware training) for the analog-CIM readout.

The StrongARM comparator's mismatch (M8: sigma ~ 10.3 mV) is a FIXED per-column offset --
baked into each manufactured column, identical every inference, NOT re-rolled noise. A
fixed offset pattern is *trainable-away*: if the network is trained with the offset
distribution in the loop, it learns weights/biases that compensate. This quantifies the
recovery on a small MLP (digits) vs offset strength, and locates our hardware's operating
point (readout SNR = N*Vstep/sigma_offset ~ 114, i.e. ~0.9% of full-scale).

Conditions per offset level:
  ideal : train clean, deploy clean                  (upper bound)
  naive : train clean, deploy on offset columns      (what you get if you ignore the HW)
  EACB  : train WITH fresh offset draws injected, deploy on offset columns

Offsets are applied at BOTH layers' pre-activations (hidden-layer offsets propagate through
ReLU nonlinearly -> not absorbable into a bias, so the recovery is non-trivial). Deployment
accuracy is averaged over many offset draws ('chips').

Run in the iic-osic-tools container (numpy + sklearn):
    docker ... bash -c 'python3 sw/eacb_demo.py'
"""
import numpy as np
from sklearn.datasets import load_digits
from sklearn.model_selection import train_test_split

rng = np.random.default_rng(0)

d = load_digits()
X = d.data / 16.0
Xtr, Xte, ytr, yte = train_test_split(X, d.target, test_size=0.3, random_state=0, stratify=d.target)
D, H, K = 64, 32, 10
Ytr = np.eye(K)[ytr]


def init():
    return dict(W1=rng.normal(0, np.sqrt(2 / D), (D, H)), b1=np.zeros(H),
                W2=rng.normal(0, np.sqrt(2 / H), (H, K)), b2=np.zeros(K))


def relu(x):
    return np.maximum(0, x)


def softmax(z):
    z = z - z.max(1, keepdims=True)
    e = np.exp(z)
    return e / e.sum(1, keepdims=True)


def forward(p, Xb, o1=0.0, o2=0.0):
    z1 = Xb @ p["W1"] + p["b1"] + o1     # analog MVM (layer 1) + fixed column offset
    a1 = relu(z1)
    z2 = a1 @ p["W2"] + p["b2"] + o2     # analog MVM (layer 2) + fixed column offset
    return z1, a1, z2, softmax(z2)


def train(os1=0.0, os2=0.0, epochs=400, lr=0.5):
    p = init()
    n = len(Xtr)
    for _ in range(epochs):
        o1 = rng.normal(0, os1, H) if os1 > 0 else 0.0   # fresh offset draw each epoch (EACB)
        o2 = rng.normal(0, os2, K) if os2 > 0 else 0.0
        z1, a1, z2, P = forward(p, Xtr, o1, o2)
        dz2 = (P - Ytr) / n
        dW2, db2 = a1.T @ dz2, dz2.sum(0)
        dz1 = (dz2 @ p["W2"].T) * (z1 > 0)
        dW1, db1 = Xtr.T @ dz1, dz1.sum(0)
        for k, g in (("W1", dW1), ("b1", db1), ("W2", dW2), ("b2", db2)):
            p[k] -= lr * g
    return p


def acc(p, o1=0.0, o2=0.0):
    return (forward(p, Xte, o1, o2)[3].argmax(1) == yte).mean()


def deploy_acc(p, os1, os2, chips=25):
    return np.mean([acc(p, rng.normal(0, os1, H), rng.normal(0, os2, K)) for _ in range(chips)])


def main():
    p0 = train()                                   # clean baseline
    z1c, _, z2c, _ = forward(p0, Xtr)
    s1, s2 = z1c.std(), z2c.std()                  # per-layer pre-activation scale
    ideal = acc(p0)
    print(f"clean pre-act std: L1={s1:.2f} L2={s2:.2f} | ideal test acc = {ideal:.3f}\n")
    print("offset (as fraction of pre-act std; HW ~0.05 = readout SNR 114)")
    print(f"{'frac':>6} | {'naive':>6} | {'EACB':>6} | {'EACB gain':>9}")
    print("-" * 50)
    for frac in (0.05, 0.10, 0.20, 0.30):
        os1, os2 = frac * s1, frac * s2
        naive = deploy_acc(p0, os1, os2)
        eacb = deploy_acc(train(os1, os2), os1, os2)
        gain = (eacb - naive) * 100
        tag = "  <- ~HW point: offset costs ~0, EACB not needed" if frac == 0.05 else ""
        print(f"{frac:>6.2f} | {naive:>6.3f} | {eacb:>6.3f} | {gain:>+6.1f} pt{tag}")


if __name__ == "__main__":
    main()
