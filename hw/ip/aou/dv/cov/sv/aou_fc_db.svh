// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Functional coverage service (singleton). Covergroup owners declare their
// groups here with the same bins tables their covergroups use and feed every
// sample() to both, so the counts don't depend on a simulator's covergroup
// engine. write_json() dumps every declared bin, hit or not, except ignored
// ones; a bin's spec names the spec revision it needs ("v0.8"), an illegal bin
// is marked "illegal", and plan_ids is a placeholder for test-plan IDs.
class aou_fc_db;
  local static aou_fc_db inst;

  aou_fc_group groups[$];
  aou_fc_group by_name[string];

  static function aou_fc_db get();
    if (inst == null) inst = new();
    return inst;
  endfunction

  // The group called name; fresh is 1 when it was just created and the caller
  // must declare its coverpoints and crosses.
  function aou_fc_group group(string name, output bit fresh);
    fresh = !by_name.exists(name);
    if (fresh) begin
      aou_fc_group g = new(name);
      groups.push_back(g);
      by_name[name] = g;
    end
    return by_name[name];
  endfunction

  // At the end of a run: +aou_fc_json=<path> writes the database there.
  static function void write_requested();
    string path;
    if ($value$plusargs("aou_fc_json=%s", path)) get().write_json(path);
  endfunction

  function void write_json(string path);
    string test = "";
    int fd;
    bit first;
    void'($value$plusargs("UVM_TESTNAME=%s", test));
    fd = $fopen(path, "w");
    if (fd == 0) begin
      `uvm_error("aou_fc_db", {"cannot write ", path})
      return;
    end
    $fwrite(fd, "{\"format\": \"aou-fc/1\", \"test\": \"%s\", \"groups\": [", test);
    foreach (groups[g]) begin
      aou_fc_group grp = groups[g];
      $fwrite(fd, "%s\n {\"group\": \"%s\", \"spec\": \"\", \"plan_ids\": [], \"samples\": %0d, ",
              g == 0 ? "" : ",", grp.name, grp.samples);
      $fwrite(fd, "\"points\": [");
      foreach (grp.pts[p]) begin
        aou_fc_point pt = grp.pts[p];
        $fwrite(fd, "%s\n  {\"point\": \"%s\", \"kind\": \"%s\", \"outside\": %0d, \"bins\": [",
                p == 0 ? "" : ",", pt.name, pt.is_cross ? "cross" : "coverpoint", pt.outside);
        first = 1'b1;
        foreach (pt.hits[b]) begin
          if (pt.kind[b] == aou_fc_point::KIND_IGNORE) continue;
          $fwrite(fd, "%s\n   {\"bin\": \"%s\", \"hits\": %0d, \"spec\": \"%s\", %s%s",
                  first ? "" : ",", pt.bin_name[b], pt.hits[b], pt.spec[b],
                  pt.kind[b] == aou_fc_point::KIND_ILLEGAL ? "\"illegal\": true, " : "",
                  "\"plan_ids\": []}");
          first = 1'b0;
        end
        $fwrite(fd, "]}");
      end
      $fwrite(fd, "]}");
    end
    $fwrite(fd, "\n]}\n");
    $fclose(fd);
  endfunction
endclass
