# Shared CV data conventions

This directory is the canonical source for the website and application CVs. CV
templates may choose different sections, ordering, date precision, or country
abbreviations, but they must derive those choices from the same records here.

## General conventions

- Use unquoted ISO dates: `YYYY-MM-DD`.
- Store full country names. Use `The Netherlands` and
  `United States of America`; templates may abbreviate them when rendering.
- Store full institution names. Do not add parallel abbreviation fields.
- Use lowercase `snake_case` values for categorical fields such as `role`,
  `format`, and `category`.
- Use `title` for the name of an activity and `institution` for its host.
- Keep presentation choices out of the records. Section titles, date formats,
  and labels such as "Invited talk" are derived by each template.
- Do not store values that can be derived reliably. Publication links come
  from `doi`, and formatted journal references come from `journal`, `vol`,
  `page`, and `published`.

## Structured records

- `talks.yaml` separates `format` (`conference`, `seminar`, `public`, or
  `online_series`) from `role` (`invited`, `contributed`, or `speaker`).
- `teaching.yml` separates `category` (`course` or `workshop`), `role`, and
  course `level`. Extra duties belong in `details`; programmes such as EdV
  belong in `program`.
- Funding amounts are mappings with integer `value`, ISO `currency`, and a
  Boolean `approximate` flag.
- Publication `vol`, `page`, and arXiv `id` values are strings; dates are ISO
  dates. `highlight` remains optional CV-selection metadata.

Validate the database and rebuild both CV variants from
`application_material` with:

```bash
pixi run validate_cv_data
pixi run build_cv
pixi run build_mariecurie_cv
```

The website's `pixi run update-publications` task runs its imported metadata
through `scripts/normalize_publications.py`, so external updates preserve these
conventions.
