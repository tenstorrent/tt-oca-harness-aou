#!/usr/bin/env bash
# *****************************************************************************
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: © 2026 VNCHIPLabs
# *****************************************************************************
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
# *****************************************************************************
#
#  File        : get_uvm_core.sh
#  Author     : Vinh Trieu, Quang Le
# *****************************************************************************
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${UVM_CORE_ROOT:-$HERE/.deps/uvm-core}"
REF=78c06547a2a0a29b3dc9dcafae62b75b2ff61544
if [[ -f "$DEST/src/uvm_pkg.sv" ]]; then
  actual="$(git -C "$DEST" rev-parse HEAD)"
  [[ "$actual" == "$REF" ]] || { echo "UVM-core at $actual, expected $REF" >&2; exit 1; }
else
  mkdir -p "$(dirname "$DEST")"
  git clone https://github.com/accellera-official/uvm-core.git "$DEST"
  git -C "$DEST" checkout --detach "$REF"
fi
