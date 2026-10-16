// *****************************************************************************
// SPDX-License-Identifier: Apache-2.0
// *****************************************************************************
//  Copyright (c) 2026 Tenstorrent USA Inc
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
// *****************************************************************************
//
//  Module     : aou_fdi_checker_pkg
//  Version    : 1.00
//  Date       : 26-09-02
//
// *****************************************************************************
//
//  AOU_FDI_CHECKER's code spaces and its check-group postures, and nothing
//  else.
//
//  THE SOURCE OF TRUTH FOR EVERY CONSUMER, INCLUDING THE PYTHON ONES. The
//  module, the standalone testbench and the loopback regression's helper all
//  take these values from here. aou_fdi_checker_pkg.py alongside this file is
//  the Python mirror, and scripts/check_checker_code_space.py fails if the two
//  disagree -- so a value added here is added there in the same change.
//
//  This package is the checker's own and is deliberately NOT shared with the
//  design. It carries the checker's opinions rather than facts about the wire
//  format: those are aou_fdi_wire_pkg's, and behavioural rules are shared
//  with nothing at all.
//
//  See DESIGN.md "The checker's package".
//
// *****************************************************************************

`timescale 1ns/1ps

package aou_fdi_checker_pkg;

// -----------------------------------------------------------------------------
// Protocol violation code space: one bit per class in O_VIOLATION, and the same
// index is the code placed in the capture record. A rule added to an existing
// class changes no interface; a new class increases VIOL_CLASS_CNT and therefore
// the status-vector width.
// See DESIGN.md "Violation reporting".
// -----------------------------------------------------------------------------
localparam int VIOL_MSGTYPE       = 0;  // reserved/undefined MSGTYPE
localparam int VIOL_MISCOP        = 1;  // reserved/undefined MISCOP
localparam int VIOL_ACTIVATIONOP  = 2;  // reserved/undefined ACTIVATIONOP
localparam int VIOL_DLENGTH       = 3;  // reserved DLENGTH encoding
localparam int VIOL_RSVD_NONZERO  = 4;  // reserved field observed non-zero
localparam int VIOL_MSGSTART      = 5;  // MsgStart inconsistent with lengths
localparam int VIOL_ACT_SEQ       = 6;  // illegal activation sequencing
localparam int VIOL_MSG_ORDER     = 7;  // credited message outside its window
localparam int VIOL_CRD_UNDERFLOW = 8;  // shadow credit would go negative
localparam int VIOL_MISC_PLACEMENT = 9; // Activation message not at granule 0
localparam int VIOL_ADV_ORDER     = 10; // credits advertised outside their window
localparam int VIOL_RP_RANGE      = 11; // plane field names a plane the link lacks
localparam int VIOL_FDID          = 12; // flit addressed to a bridge this instance does not watch
localparam int VIOL_CRD_OVERFLOW  = 13; // more credit advertised than a shadow counter can hold
localparam int VIOL_RP_MAP        = 14; // I_CFG_RP_DEST_RP maps two planes onto one

localparam int VIOL_CLASS_CNT     = 15;
localparam int VIOL_CODE_WD       = $clog2(VIOL_CLASS_CNT);

// -----------------------------------------------------------------------------
// Rule groups, and the classes each one owns.
//
// EVERY CLASS BELONGS TO EXACTLY ONE GROUP, which AOU_FDI_CHECKER checks at
// elaboration -- so a class added above without being placed in a group here
// fails the build rather than becoming unreportable.
//
// Masks in O_VIOLATION's bit space, built from the codes above rather than
// written out, so that renumbering a class cannot leave a mask naming the bit
// it used to have. See DESIGN.md "Selectable check groups".
// -----------------------------------------------------------------------------
localparam int CHK_CLASSES_STRUCT    = (1 << VIOL_MSGTYPE)      |
                                       (1 << VIOL_MISCOP)       |
                                       (1 << VIOL_ACTIVATIONOP) |
                                       (1 << VIOL_DLENGTH)      |
                                       (1 << VIOL_RSVD_NONZERO) |
                                       (1 << VIOL_RP_RANGE)     |
                                       (1 << VIOL_FDID)         |
                                       (1 << VIOL_RP_MAP);
localparam int CHK_CLASSES_FRAMING   = (1 << VIOL_MSGSTART) |
                                       (1 << VIOL_MISC_PLACEMENT);
localparam int CHK_CLASSES_ACT_SEQ   = (1 << VIOL_ACT_SEQ);
localparam int CHK_CLASSES_MSG_ORDER = (1 << VIOL_MSG_ORDER) |
                                       (1 << VIOL_ADV_ORDER);
localparam int CHK_CLASSES_CREDIT    = (1 << VIOL_CRD_UNDERFLOW) |
                                       (1 << VIOL_CRD_OVERFLOW);

localparam int CHK_CLASSES_ALL       = CHK_CLASSES_STRUCT    |
                                       CHK_CLASSES_FRAMING   |
                                       CHK_CLASSES_ACT_SEQ   |
                                       CHK_CLASSES_MSG_ORDER |
                                       CHK_CLASSES_CREDIT;

// -----------------------------------------------------------------------------
// Named profiles: the postures a bench selects, rather than a set of booleans
// it has to get right. Every group is selectable, so this set is complete: a
// posture outside it is reached by setting one group's enable directly.
// -----------------------------------------------------------------------------
localparam int CHK_PROFILE_FULL        = 0;  // every rule group
localparam int CHK_PROFILE_NO_CREDIT   = 1;  // everything but credit accounting
// Structural encodings and message-start framing: the rules a single flit can
// be judged against on its own. Named for what it keeps rather than for what it
// drops, because it is the posture with no model of the link behind it at all
// -- no activation state, no credit counters -- which is what a bench observing
// a partner chiplet, or one stream of a link, is left with.
localparam int CHK_PROFILE_WELL_FORMED = 2;
// Structural encodings alone. The spanning-grant pending flag and first
// granule are retained so reserved bits in a grant crossing G47->G0 are checked.
localparam int CHK_PROFILE_STRUCTURAL  = 3;
// Exactly the rules CHK_PROFILE_WELL_FORMED drops, and named for the same
// thing it is named for: these are the rules that need a model of the link. For
// a bench chasing an activation or credit bug on a peer whose encoder it
// already trusts, and which does not want forty-eight encoding reports out of
// one malformed flit standing between it and the finding.
localparam int CHK_PROFILE_LINK_MODEL  = 4;

// What each profile must resolve to on O_CHECK_ENABLED.
//
// SAID HERE INDEPENDENTLY OF THE MODULE, and that is the point: the module
// resolves a profile into group enables and reports the classes those cover,
// while this says what the answer should be. A test comparing the two is
// therefore a comparison rather than a tautology, which is what puts the
// enable output itself under test rather than trusted.
localparam int CHK_PROFILE_CLASSES_FULL        = CHK_CLASSES_ALL;
localparam int CHK_PROFILE_CLASSES_NO_CREDIT   = CHK_CLASSES_ALL &
                                                 ~CHK_CLASSES_CREDIT;
localparam int CHK_PROFILE_CLASSES_WELL_FORMED = CHK_CLASSES_STRUCT |
                                                 CHK_CLASSES_FRAMING;
localparam int CHK_PROFILE_CLASSES_STRUCTURAL  = CHK_CLASSES_STRUCT;
localparam int CHK_PROFILE_CLASSES_LINK_MODEL  = CHK_CLASSES_ALL &
                                                 ~CHK_PROFILE_CLASSES_WELL_FORMED;

// -----------------------------------------------------------------------------
// Cross-check violation code space, deliberately its own: these share no bit,
// code, capture record or trigger with a protocol violation.
// See DESIGN.md "Cross-check reporting".
// -----------------------------------------------------------------------------
localparam int XVIOL_TIMEOUT      = 0;  // design never converged on the checker's state
localparam int XVIOL_MISMATCH     = 1;  // both settled, still disagreeing

localparam int XVIOL_CLASS_CNT    = 2;
localparam int XVIOL_CODE_WD      = $clog2(XVIOL_CLASS_CNT);

// -----------------------------------------------------------------------------
// Cross-check settling interval and convergence window defaults, in cycles.
//
// TIGHTEN ONLY WITH EVIDENCE. These are roughly fifteen and a hundred times the
// worst cases in DESIGN.md "The budget behind the defaults", and every cycle
// taken off is a cycle of margin against a false positive -- which is the kind
// of thing that gets a checker switched off.
// -----------------------------------------------------------------------------
localparam int XCHK_SETTLE_CYCLES_DEFAULT   = 4096;
localparam int XCHK_CONVERGE_CYCLES_DEFAULT = 1024;

endpackage
