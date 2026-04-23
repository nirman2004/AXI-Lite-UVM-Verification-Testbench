# AXI-Lite UVM Verification Testbench

![SystemVerilog](https://img.shields.io/badge/SystemVerilog-UVM-blue?style=flat-square&logo=verilog)
![Simulator](https://img.shields.io/badge/Simulator-QuestaSim%20%7C%20EDA%20Playground-green?style=flat-square)
![Status](https://img.shields.io/badge/Status-Passing%2010%2F10%20Transactions-brightgreen?style=flat-square)
![Coverage](https://img.shields.io/badge/Coverage-Functional%20%2B%20Cross-orange?style=flat-square)

A fully-structured **UVM (Universal Verification Methodology)** testbench for an **AXI-Lite write slave**, implementing the complete verification stack — driver, monitor, scoreboard, sequencer, coverage collector, SVA assertions, and waveform validation.

---

## 📐 Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│                    my_test (uvm_test)                │
│                                                     │
│   ┌────────────┐    ┌──────────┐    ┌───────────┐  │
│   │ Sequencer  │───▶│  Driver  │    │  Monitor  │  │
│   └────────────┘    └────┬─────┘    └─────┬─────┘  │
│                          │                │         │
│                    ┌─────▼────────────────▼──────┐  │
│                    │        axi_if (Interface)    │  │
│                    └─────────────┬───────────────┘  │
│                                  │                   │
│                    ┌─────────────▼───────────────┐  │
│                    │     axi_slave_dummy (DUT)    │  │
│                    └─────────────────────────────┘  │
│                                                     │
│   ┌──────────────┐    ┌──────────────────────────┐  │
│   │  Scoreboard  │◀───│  uvm_analysis_port (ap)  │  │
│   └──────────────┘    └──────────────────────────┘  │
│                                                     │
│   ┌──────────────┐    ┌──────────────────────────┐  │
│   │  Coverage    │    │     SVA Assertions        │  │
│   │  (cg group)  │    │  (axi_assertions module)  │  │
│   └──────────────┘    └──────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

---

## 📁 File Structure

```
axi-lite-uvm-tb/
├── testbench.sv          # Top-level: all UVM components, DUT, interface, test
└── README.md
```

> All components are implemented in a single self-contained SystemVerilog file for portability on EDA Playground.

---

## 🧩 Components

### Interface — `axi_if`
Defines AXI-Lite write channel signals:

| Signal     | Direction | Description               |
|------------|-----------|---------------------------|
| `awaddr`   | Master→Slave | Write address             |
| `awvalid`  | Master→Slave | Address valid             |
| `awready`  | Slave→Master | Address ready             |
| `wdata`    | Master→Slave | Write data                |
| `wvalid`   | Master→Slave | Data valid                |
| `wready`   | Slave→Master | Data ready                |
| `bvalid`   | Slave→Master | Write response valid      |
| `bready`   | Master→Slave | Response ready            |

---

### Transaction — `axi_txn`
Randomizable sequence item carrying `addr [31:0]` and `data [31:0]`.

---

### Driver — `axi_driver`
- Waits for reset de-assertion
- Drives AW and W channels simultaneously (AXI-Lite write)
- Waits for `awready` + `wready` handshake before de-asserting valids
- Waits for `bvalid`, asserts `bready` for one cycle to complete the write response channel

---

### Sequence — `axi_sequence`
- Generates **10 constrained-random write transactions**
- Address constraint: `addr inside {[0:15]}`
- Data is fully random (`[31:0]`)

---

### Monitor — `axi_monitor`
- Observes AW and W channel handshakes on the interface
- Reconstructs `axi_txn` objects and broadcasts via `uvm_analysis_port`
- Triggers functional **coverage sampling** on every captured transaction

---

### Scoreboard — `axi_scoreboard`
- Receives transactions via `uvm_analysis_imp`
- Checks: `addr inside {[0:15]}` → logs **PASS**; else flags `UVM_ERROR`

---

### Coverage — `axi_monitor::cg` (covergroup)

```
ADDR bins:
  addr_low  → [0:7]
  addr_high → [8:15]

DATA bins:
  data_low  → [0:100]
  data_high → [101:500]

CROSS coverage: ADDR × DATA (4 cross bins)
```

---

### Assertions — `axi_assertions`

| Property        | Checks |
|----------------|--------|
| `aw_handshake` | `awvalid` must be followed by `awready` within bounded cycles |
| `w_handshake`  | `wvalid` must be followed by `wready` within bounded cycles  |

---

### DUT — `axi_slave_dummy`
A simple AXI-Lite write slave that:
- Asserts `awready` and `wready` by default (always-ready slave)
- Asserts `bvalid` upon observing a complete AW + W handshake
- De-asserts `bvalid` after the B-channel handshake completes

---

## 🖥️ Simulation Results

### Log Output (QuestaSim)

All 10 transactions pass scoreboard validation:

```
# UVM_INFO @ 35000:  uvm_test_top.scb [SCB] PASS addr=e data=bcc02c4d
# UVM_INFO @ 65000:  uvm_test_top.scb [SCB] PASS addr=5 data=470ae848
# UVM_INFO @ 95000:  uvm_test_top.scb [SCB] PASS addr=6 data=ff2a5bda
# UVM_INFO @ 125000: uvm_test_top.scb [SCB] PASS addr=3 data=adbbf038
# UVM_INFO @ 155000: uvm_test_top.scb [SCB] PASS addr=7 data=2a5ad9c4
# UVM_INFO @ 185000: uvm_test_top.scb [SCB] PASS addr=8 data=de60899a
# UVM_INFO @ 215000: uvm_test_top.scb [SCB] PASS addr=f data=56c0470c
# UVM_INFO @ 245000: uvm_test_top.scb [SCB] PASS addr=d data=c510a442
# UVM_INFO @ 275000: uvm_test_top.scb [SCB] PASS addr=d data=dd42d11e
# UVM_INFO @ 305000: uvm_test_top.scb [SCB] PASS addr=1 data=afd96050
```

### Waveform (EPWave)

AXI-Lite handshake waveform showing correct `awvalid/awready`, `wvalid/wready`, and `bvalid/bready` sequencing across all 10 transactions:

> ✅ `awready` = 1 (always-ready slave)  
> ✅ `awvalid` pulses per transaction  
> ✅ `bvalid` asserts after each AW+W handshake  
> ✅ `bready` handshakes and de-asserts `bvalid`

---

## ▶️ How to Run

### On EDA Playground

1. Go to [https://edaplayground.com](https://edaplayground.com)
2. Select **Questa Sim** as the simulator
3. Enable **"Open EPWave after run"**
4. Paste `testbench.sv` into the design editor
5. Click **Run**

### Locally (QuestaSim)

```bash
vlog -sv testbench.sv +incdir+$UVM_HOME/src $UVM_HOME/src/uvm_pkg.sv
vsim -c top -do "run -all; quit"
```

---

## 🔧 Key Concepts Demonstrated

| Concept | Implementation |
|--------|---------------|
| UVM Component Hierarchy | test → sequencer → driver → monitor → scoreboard |
| AXI-Lite Protocol | AW + W + B channel handshakes |
| Constrained Randomization | `addr inside {[0:15]}` with `tx.randomize() with {}` |
| Functional Coverage | Cross-coverage: address bins × data bins |
| SystemVerilog Assertions | Handshake liveness properties |
| UVM Analysis Port | Decoupled monitor → scoreboard communication |
| Config DB | `uvm_config_db` for virtual interface passing |

---

## 👤 Author

**Nirman Dey**  
B.Tech ECE — Jalpaiguri Government Engineering College  
[LinkedIn](https://linkedin.com/in/nirman-dey-554140238) · [GitHub](https://github.com/nirman2004)

---

## 📄 License

This project is open-source and available under the [MIT License](LICENSE).
