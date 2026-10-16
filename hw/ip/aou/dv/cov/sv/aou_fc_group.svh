// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// The service's copy of one covergroup: coverpoints first, in the order
// sample() takes their values, then crosses over them. Every instance of the
// owning class feeds the same group, as the covergroup's type coverage does.
class aou_fc_group;
  localparam int MAX_CP = 8;

  string         name;
  aou_fc_point   pts[$];
  int unsigned   n_cp;
  longint unsigned samples;

  function new(string group_name);
    name = group_name;
  endfunction

  function aou_fc_point cp(string cp_name);
    aou_fc_point p = new(cp_name, 1'b0, name);
    if (n_cp != pts.size())
      `uvm_fatal("aou_fc_group", $sformatf("%s: coverpoint %s after a cross", name, cp_name))
    if (n_cp == MAX_CP)
      `uvm_fatal("aou_fc_group", $sformatf("%s: more than %0d coverpoints", name, MAX_CP))
    pts.push_back(p);
    n_cp++;
    return p;
  endfunction

  // cps names the crossed coverpoints, separated by spaces.
  function aou_fc_point add_cross(string x_name, string cps);
    aou_fc_point p = new(x_name, 1'b1, name);
    string w = "";
    for (int i = 0; i <= cps.len(); i++) begin
      if (i == cps.len() || cps[i] == " ") begin
        if (w != "") p.comp.push_back(cp_index(w));
        w = "";
      end else begin
        w = {w, string'(cps[i])};
      end
    end
    p.make_cross(pts);
    pts.push_back(p);
    return p;
  endfunction

  function int unsigned cp_index(string cp_name);
    for (int unsigned i = 0; i < n_cp; i++) if (pts[i].name == cp_name) return i;
    `uvm_fatal("aou_fc_group", $sformatf("%s: no coverpoint %s", name, cp_name))
    return 0;
  endfunction

  // One value per coverpoint, in declaration order.
  function void sample(int v0, int v1 = 0, int v2 = 0, int v3 = 0,
                       int v4 = 0, int v5 = 0, int v6 = 0, int v7 = 0);
    int v[MAX_CP];
    v = '{v0, v1, v2, v3, v4, v5, v6, v7};
    samples++;
    for (int unsigned i = 0; i < n_cp; i++) pts[i].sample(v[i]);
    for (int unsigned i = n_cp; i < pts.size(); i++) pts[i].sample_cross(pts);
  endfunction
endclass
