# CNN Hardware Accelerator

A **Low Power 2D Systolic Array** based hardware accelerator designed for high-speed CNN inference.

---

## Training Results

| Model | Accuracy | Quantization Error |
| :--- | :--- | :--- |
| **VGGNet** (4-bit act, 4-bit weights) | 90% | 3.9101e-07 |
| **VGGNet** (2-bit act, 4-bit weights) | 90% | 5.5854e-07 |

---

## Architecture Design

### Alpha 1: 2-bit/4-bit Array with OS/WS

The architecture provides flexibility to use higher or lower bit precisions and utilizes hardware efficiently on layers with fewer than 8 input channels through **Output Stationary (OS)** mapping.

* **Weight Stationary (WS) Mode** (`mode_sel = 0`):
    - **2-bit**: Loads weights into R/L registers over two phases.
    - **4-bit**: Uses the same 2-bit MACs; MSBs are shifted by 2.
* **Output Stationary (OS) Mode** (`mode_sel = 1`):
    - **4-bit Default**: Each PE computes one output, accumulating until all channels finish.
    - **2-bit**: Splits each PE into two 2-bit lanes, producing two outputs in parallel.

### Alpha 2: Tiling on 2-bit WS

- The **MAC array** handles 16 input by 8 output channels simultaneously.
- Tiling for 16x16 channels is performed in the testbench by offsetting memory access in control registers.
- Tiling capability extends to the combined 2/4-bit array with OS/WS functionality.

---

## Verification & Optimization

### Alpha 3: Random Stimulus Testbench

A robust verification environment using **C functions** to create random activations and calculate expected outputs based on given model weights. This is integrated into a **SystemVerilog testbench** for maximum coverage.

### Alpha 4: Clock Gating & MAC Skipping

MAC operations dominate dynamic power consumption (approximately 80%). To optimize efficiency:

* **Gated Clock**: Disables the MAC when either the activation or weight is zero; inputs and partial sums simply pass through.
* **Results**: With 80% weight sparsity, **80% of MACs are skipped**, cutting dynamic power by **64%**.
* **Power Efficiency**: Overall improvement of approximately **2.78x**.


---

## Performance and Synthesis

### Alpha 5: Mapping ResNet

Testing on **ResNet20** (Layer 3 to 8) showed lower tolerance to channel bottlenecking compared to VGGNet:

- **4-bit Model**: 86.58% accuracy (3e-6 error).
- **2-bit Model**: 73.25% accuracy (1e-6 error).

### Alpha 6: FPGA Synthesis Results

The design was synthesized on a **Cyclone IV FPGA**.

| Metric | 4-bit act. WS (Pt 1) | Alpha 1 (Final Design) |
| :--- | :--- | :--- |
| **Total Ops / Cycle** | 128 | 256 |
| **Frequency** | 129.82 MHz | 93.46 MHz |
| **Logic Elements** | 16,681 (11%) | 30,889 (21%) |
| **Registers** | 11,936 | 15,802 |
| **Dynamic Power** | 172 mW | 173 mW |
| **Performance (TOPs)** | 16.6 GOPS | 23.9 GOPS |
| **Efficiency (TOPs/W)** | 96.6 GOPS/W | **138 GOPS/W** |

---

## Conclusion

The final design (Alpha 1) observed a **43% increase** in both TOPs and TOPs/W efficiency.