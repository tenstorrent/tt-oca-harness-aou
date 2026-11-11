// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Functional coverage service (singleton). Covergroup owners declare their
// groups here with the same bins tables their covergroups use and feed every
// sample() to both, so the counts don't depend on a simulator's covergroup
// engine. write_json() dumps every declared bin, hit or not, except ignored
// ones; a bin's spec names the spec revision it needs ("v0.8"), an illegal bin
// is marked "illegal". plan_ids lists the test-plan items a group's bins all
// serve (aou_fc_group::plan) and, per bin, every item that bin serves.
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
      $fwrite(fd, "%s\n {\"group\": \"%s\", \"spec\": \"\", \"plan_ids\": %s, \"samples\": %0d, ",
              g == 0 ? "" : ",", grp.name, json_ids(grp.plan_ids), grp.samples);
      $fwrite(fd, "\"points\": [");
      foreach (grp.pts[p]) begin
        aou_fc_point pt = grp.pts[p];
        $fwrite(fd, "%s\n  {\"point\": \"%s\", \"kind\": \"%s\", \"outside\": %0d, \"bins\": [",
                p == 0 ? "" : ",", pt.name, pt.is_cross ? "cross" : "coverpoint", pt.outside);
        first = 1'b1;
        foreach (pt.hits[b]) begin
          if (pt.kind[b] == aou_fc_point::KIND_IGNORE) continue;
          $fwrite(fd, "%s\n   {\"bin\": \"%s\", \"hits\": %0d, \"spec\": \"%s\", ",
                  first ? "" : ",", pt.bin_name[b], pt.hits[b], pt.spec[b]);
          if (pt.kind[b] == aou_fc_point::KIND_ILLEGAL)
            $fwrite(fd, "\"illegal\": true, ");
          $fwrite(fd, "\"plan_ids\": %s}", json_ids({grp.plan_ids, " ", pt.plan[b]}));
          first = 1'b0;
        end
        $fwrite(fd, "]}");
      end
      $fwrite(fd, "]}");
    end
    $fwrite(fd, "\n]}\n");
    $fclose(fd);
  endfunction

  // Space-separated IDs as a JSON array of strings, each once.
  static function string json_ids(string ids);
    string w[$];
    bit seen[string];
    string s = "";
    aou_fc_point::split(ids, " ", w);
    foreach (w[i]) begin
      if (w[i] == "" || seen.exists(w[i])) continue;
      seen[w[i]] = 1'b1;
      if (s != "") s = {s, ", "};
      s = {s, "\"", w[i], "\""};
    end
    return {"[", s, "]"};
  endfunction
endclass
