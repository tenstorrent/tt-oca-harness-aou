// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// APB agent plus the register model generated from csr/aou-core.rdl, with
// explicit prediction from the APB monitor. A parent environment can pass its
// own model through config_db key "regmodel".
class aou_reg_env extends uvm_env;
  `uvm_component_utils(aou_reg_env)

  aou_apb_cfg                       apb_cfg;
  aou_apb_agent                     apb;
  aou_core                          regmodel;
  uvm_reg_predictor #(aou_apb_item) predictor;
  // 1 while nothing but APB accesses can change register state.
  bit                               quiet = 1'b1;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (apb_cfg == null && !uvm_config_db#(aou_apb_cfg)::get(this, "", "apb_cfg", apb_cfg))
      apb_cfg = aou_apb_cfg::type_id::create("apb_cfg");
    apb = aou_apb_agent::type_id::create("apb", this);
    apb.cfg = apb_cfg;
    if (!uvm_config_db#(aou_core)::get(this, "", "regmodel", regmodel))
      regmodel = create_model();
    aou_reg_policy::apply(regmodel, quiet);
    predictor = uvm_reg_predictor#(aou_apb_item)::type_id::create("predictor", this);
  endfunction

  // Builds and locks the generated model. PeakRDL-uvm creates the map with
  // UVM_NO_ENDIAN, which uvm-core 2020 refuses for any access; every register
  // is one bus word, so little-endian changes nothing else. A parent env that
  // builds its own model must do the same before lock_model().
  static function aou_core create_model(string name = "aou_core");
    aou_core m = new(name);
    m.build();
    m.default_map.configure(m, 0, 4, UVM_LITTLE_ENDIAN, 1);
    m.lock_model();
    return m;
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    apb.connect_reg_map(regmodel.default_map);
    apb.connect_predictor(predictor, regmodel.default_map);
  endfunction
endclass
