# FreeBSD Release Notes Helper Tools

License: BSD-2-Clause
Copyright (c) The FreeBSD Project

---

## Overview

This repository contains helper tools used to collect, review, curate, and generate FreeBSD release notes in a controlled and auditable way.

The workflow is intentionally split into multiple stages in order to clearly separate:

- automatic data collection from Git
- manual review and classification
- final AsciiDoc generation

Each stage produces a plain text artifact that can be inspected, version-controlled, and edited when required.

---

## High-level Workflow

The release notes process consists of three sequential stages:

1. Automatic collection of commits from Git (Stage 1)
2. Manual review, classification, and acceptance (Stage 2)
3. Generation and update of the final relnotes.adoc file

Each stage reads the output of the previous one and adds more structure and intent.

---

## Stage 1 — Collecting Commits

### Purpose

Stage 1 automatically collects commit information from Git and normalizes it into a structured text format suitable for further processing.

This stage is fully automatic and should not require manual edits.

### Output

The result is a file named `relnotes_stage1.txt`.

Each record contains:

- commit hash
- commit date (ISO 8601)
- score (default value is 5)
- subject
- full commit body

---

## Stage 2 — Review and Curation

### Purpose

Stage 2 converts raw commit data into a form suitable for human review and editorial decisions.

During this stage:

- new commits are transferred from stage1
- duplicates are avoided
- initial metadata is assigned

### Manual Review

The resulting file, `relnotes_stage2.txt`, is intended to be edited manually.

Editors typically:

- change `Status` to `accepted` or `rejected`
- assign a meaningful `Section`
- refine subject and description text
- adjust score if needed

---

## Sections Mapping

Release note sections are defined in a CSV file called `sections.csv`.

Each entry maps a logical section name to:

- an AsciiDoc anchor
- a human-readable section title

The sections file is searched in this order:

1. the release directory
2. the default sections file shipped with the tools

This allows per-release customization without modifying the tools themselves.

---

## Stage 3 — Generating AsciiDoc

### Purpose

Stage 3 takes curated data from stage2 and merges it into the real `relnotes.adoc` document.

Only records that meet all criteria are considered:

- `Status` must be `accepted`
- `Section` must be set and not equal to `undecided`
- the commit must not already be documented

---

## Duplicate Protection

Before inserting anything, the tool scans `relnotes.adoc` for existing Git references in the form:

`gitref:<hash>[repository=src]`

Commit hashes are compared using prefix matching, so both short and long hashes are handled correctly.

If a commit is already present, it is skipped.

---

## Insertion Rules

- Existing content in `relnotes.adoc` is never modified
- New entries are inserted at the end of the corresponding section
- Insertion happens immediately before the next section anchor
- Each section is handled independently

---

## Sorting Rules

Sorting is applied only to newly inserted entries.

Within a section, new entries are ordered by:

1. score (descending)
2. date (descending)

Existing text keeps its original order.

---

## Dry-run and Write Modes

### Dry-run

When run with `--dry-run`, the tool:

- does not modify any files
- prints the planned insertions to standard output
- allows safe review before applying changes

### Write Mode

When run with `--write`, the tool:

- applies the same logic as dry-run
- updates `relnotes.adoc` in place

---

## Design Principles

- Plain text formats are preferred at every stage
- Each stage has a single, clear responsibility
- Manual control is preserved where editorial judgment is required
- Automation is used where it is safe and repeatable

---

## Command-line Examples

### Stage 1: Collect commits from Git

Collect commits and generate the initial stage1 file:


```
perl relnotes_stage1_from_git.pl \
  --release-dir /path/to/release
```

Resulting file:

```
/path/to/release/relnotes_stage1.txt
```

### Stage 2: Prepare and review stage2 file

Transfer new entries into the editable stage2 file:

```
perl relnotes_stage1_to_stage2.pl \
  --release-dir /path/to/release
```

After this step, manually edit:

```
/path/to/release/relnotes_stage2.txt
```

Typical manual actions:

* set `Status: accepted` or `rejected`
* assign `Section`
* adjust `Subject` and `Body`
* optionally tune `Score`

### Stage 3: Preview AsciiDoc changes (dry-run)

Show what would be inserted into `relnotes.adoc` without modifying files:


```
perl relnotes_stage2_to_adoc.pl \
  --release-dir /path/to/release \
  --dry-run
```

In this mode:

* no files are written
* planned insertions are grouped by section
* already documented commits are skipped

### Stage 3: Write changes into relnotes.adoc

Apply the changes to `relnotes.adoc`:

```
perl relnotes_stage2_to_adoc.pl \
  --release-dir /path/to/release \
  --write
```

Behavior:

* new entries are appended to the correct sections
* existing AsciiDoc content is preserved
* duplicate commits are not re-inserted

### Typical workflow summary

```
# Stage 1
perl relnotes_stage1_from_git.pl --release-dir /path/to/release

# Stage 2
perl relnotes_stage1_to_stage2.pl --release-dir /path/to/release
vi /path/to/release/relnotes_stage2.txt

# Stage 3 (preview)
perl relnotes_stage2_to_adoc.pl --release-dir /path/to/release --dry-run

# Stage 3 (apply)
perl relnotes_stage2_to_adoc.pl --release-dir /path/to/release --write
```

### Running Tests

All tests are written using Perl TAP and are executed with `prove`.

#### Run all tests

```
prove -lv t
```

=== Run a single test file

```
prove -lv t/sections.t
```

```
prove -lv t/format_read_file.t
```

```
prove -lv t/format_append_file.t
```


## License

This project is distributed under the BSD 2-Clause License.
