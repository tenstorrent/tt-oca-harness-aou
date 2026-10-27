// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Activation control: requests activation (AOU_INIT.ACTIVATE_START), deactivation (DEACTIVATE_START) or a
// forced deactivation (AOU_CON0.DEACTIVATE_FORCE), and polls AOU_INIT for the
// resulting state when wait_done is set.
class aou_reg_activation_seq extends aou_reg_base_seq;
  `uvm_object_utils(aou_reg_activation_seq)

  aou_reg_activation_op_e op = AOU_REG_ACTIVATE;
  bit          wait_done = 1'b1;
  int unsigned max_polls = 200;
  // Result: the requested state was reached (always 0 when wait_done is 0).
  bit          done;

  function new(string name = "aou_reg_activation_seq");
    super.new(name);
  endfunction

  task body();
    uvm_reg_field state;
    uvm_reg_data_t v;
    case (op)
      AOU_REG_ACTIVATE:   want(rm.aou_init.activate_start, 1);
      AOU_REG_DEACTIVATE: want(rm.aou_init.deactivate_start, 1);
      default:            want(rm.aou_con0.deactivate_force, 1);
    endcase
    commit();
    done = 1'b0;
    if (!wait_done) return;
    state = (op == AOU_REG_ACTIVATE) ? rm.aou_init.activate_state_enabled
                                     : rm.aou_init.activate_state_disabled;
    repeat (max_polls) begin
      rd_field(state, v);
      if (v == 1) begin
        done = 1'b1;
        return;
      end
    end
    `uvm_error(get_type_name(), $sformatf("%s: %s still 0 after %0d polls", op.name(),
                                          state.get_full_name(), max_polls))
  endtask
endclass
