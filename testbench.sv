`timescale 1ns/1ps
`include "uvm_macros.svh"
import uvm_pkg::*;

// ============================
// INTERFACE
// ============================
interface axi_if(input logic clk);

  logic rst_n;

  logic [31:0] awaddr;
  logic awvalid, awready;

  logic [31:0] wdata;
  logic wvalid, wready;

  logic bvalid, bready;

endinterface


// ============================
// TRANSACTION
// ============================
class axi_txn extends uvm_sequence_item;

  rand bit [31:0] addr;
  rand bit [31:0] data;

  `uvm_object_utils(axi_txn)

  function new(string name="axi_txn");
    super.new(name);
  endfunction

endclass


// ============================
// DRIVER (CORRECT AXI)
// ============================
class axi_driver extends uvm_driver #(axi_txn);

  virtual axi_if vif;

  `uvm_component_utils(axi_driver)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    if (!uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif))
      `uvm_fatal("DRV", "No VIF")
  endfunction

  task run_phase(uvm_phase phase);
    axi_txn tx;

    // wait reset
    @(posedge vif.rst_n);

    forever begin
      seq_item_port.get_next_item(tx);

      // Drive AW + W together (AXI-lite simple)
      @(posedge vif.clk);
      vif.awaddr  <= tx.addr;
      vif.awvalid <= 1;

      vif.wdata  <= tx.data;
      vif.wvalid <= 1;

      // Wait handshake
      wait(vif.awready && vif.wready);

      @(posedge vif.clk);
      vif.awvalid <= 0;
      vif.wvalid  <= 0;

      // Wait response
      wait(vif.bvalid);

      vif.bready <= 1;
      @(posedge vif.clk);
      vif.bready <= 0;

      seq_item_port.item_done();
    end
  endtask

endclass


// ============================
// SEQUENCE
// ============================
class axi_sequence extends uvm_sequence #(axi_txn);

  `uvm_object_utils(axi_sequence)

  function new(string name="axi_sequence");
    super.new(name);
  endfunction

  task body();
    axi_txn tx;

    repeat (10) begin
      tx = axi_txn::type_id::create("tx");

      assert(tx.randomize() with {
        addr inside {[0:15]};
      });

      start_item(tx);
      finish_item(tx);
    end
  endtask

endclass


// ============================
// MONITOR + COVERAGE
// ============================
class axi_monitor extends uvm_component;

  virtual axi_if vif;
  uvm_analysis_port #(axi_txn) ap;

 covergroup cg;
  option.per_instance = 1;

  ADDR: coverpoint vif.awaddr {
    bins addr_low  = {[0:7]};
    bins addr_high = {[8:15]};
  }

  DATA: coverpoint vif.wdata {
    bins data_low  = {[0:100]};
    bins data_high = {[101:500]};
  }

  CROSS: cross ADDR, DATA;
endgroup

  `uvm_component_utils(axi_monitor)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
    cg = new();
  endfunction

  function void build_phase(uvm_phase phase);
    if (!uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif))
      `uvm_fatal("MON", "No VIF")
  endfunction

  task run_phase(uvm_phase phase);
    axi_txn tx;

    forever begin
      @(posedge vif.clk);

      if (vif.awvalid && vif.awready) begin
        tx = axi_txn::type_id::create("tx");
        tx.addr = vif.awaddr;

        wait(vif.wvalid && vif.wready);
        tx.data = vif.wdata;

        cg.sample();
        ap.write(tx);

        `uvm_info("MON",
          $sformatf("addr=%0h data=%0h", tx.addr, tx.data),
          UVM_LOW)
      end
    end
  endtask

endclass


// ============================
// SCOREBOARD
// ============================
class axi_scoreboard extends uvm_component;

  uvm_analysis_imp #(axi_txn, axi_scoreboard) imp;

  `uvm_component_utils(axi_scoreboard)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    imp = new("imp", this);
  endfunction

  function void write(axi_txn tx);
    if (tx.addr inside {[0:15]})
      `uvm_info("SCB",
        $sformatf("PASS addr=%0h data=%0h", tx.addr, tx.data),
        UVM_LOW)
    else
      `uvm_error("SCB", "ADDR OUT OF RANGE")
  endfunction

endclass


// ============================
// DUT (FIXED)
// ============================
module axi_slave_dummy(axi_if vif);

  always @(posedge vif.clk or negedge vif.rst_n) begin

    if (!vif.rst_n) begin
      vif.awready <= 0;
      vif.wready  <= 0;
      vif.bvalid  <= 0;
    end
    else begin
      vif.awready <= 1;
      vif.wready  <= 1;

      if (vif.awvalid && vif.awready &&
          vif.wvalid && vif.wready) begin
        vif.bvalid <= 1;
      end
      else if (vif.bvalid && vif.bready) begin
        vif.bvalid <= 0;
      end
    end

  end

endmodule


// ============================
// ASSERTIONS
// ============================
module axi_assertions(axi_if vif);

  property aw_handshake;
    @(posedge vif.clk)
    vif.awvalid |-> ##[1:$] vif.awready;
  endproperty

  property w_handshake;
    @(posedge vif.clk)
    vif.wvalid |-> ##[1:$] vif.wready;
  endproperty

  assert property(aw_handshake);
  assert property(w_handshake);

endmodule


// ============================
// TOP
// ============================
module top;

  logic clk;
  initial clk = 0;
  always #5 clk = ~clk;

  axi_if vif(clk);

  axi_slave_dummy dut(vif);
  axi_assertions sva(vif);

  // RESET
  initial begin
    vif.rst_n = 0;
    #20;
    vif.rst_n = 1;
  end

  initial begin
    uvm_config_db#(virtual axi_if)::set(null, "*", "vif", vif);
    run_test("my_test");
  end

  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, top);
  end

endmodule


// ============================
// TEST
// ============================
class my_test extends uvm_test;

  `uvm_component_utils(my_test)

  axi_driver drv;
  axi_monitor mon;
  axi_scoreboard scb;
  uvm_sequencer #(axi_txn) seqr;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    drv  = axi_driver::type_id::create("drv", this);
    mon  = axi_monitor::type_id::create("mon", this);
    scb  = axi_scoreboard::type_id::create("scb", this);
    seqr = uvm_sequencer#(axi_txn)::type_id::create("seqr", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    drv.seq_item_port.connect(seqr.seq_item_export);
    mon.ap.connect(scb.imp);
  endfunction

  task run_phase(uvm_phase phase);

    axi_sequence seq;

    phase.raise_objection(this);

    seq = axi_sequence::type_id::create("seq");
    seq.start(seqr);

    // allow all 10 transactions
    #1000;

    phase.drop_objection(this);

  endtask

endclass