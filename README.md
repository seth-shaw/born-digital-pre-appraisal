# Document to Markdown converter

This project builds a Docker image containing LibreOffice Writer, Pandoc, the
`file` utility, and the headless Java components needed for clean LibreOffice
startup. The container scans a mounted directory, identifies documents by
their detected file type rather than their filename extension, and writes
files in the requested Pandoc output format beside the source documents.

Legacy Word documents and formats such as WordPerfect are normalized to DOCX
with LibreOffice before Pandoc converts them to GitHub-Flavored Markdown.

## Build the image

From this directory, run:

```sh
docker build -t doc-converter .
```

## Convert a directory

Place the documents to convert in a directory such as `./documents`, then run
the container with that directory mounted at `/work/input`:

### PowerShell

```powershell
docker run --rm `
  --mount "type=bind,source=${PWD}\documents,target=/work/input" `
  doc-converter /work/input
```

To export to HTML, pass `html` as the second argument:

```powershell
docker run --rm `
  --mount "type=bind,source=${PWD}\documents,target=/work/input" `
  doc-converter /work/input html
```

### Linux/macOS shell

```sh
docker run --rm \
  --mount "type=bind,source=$(pwd)/documents,target=/work/input" \
  doc-converter /work/input
```

The second argument selects the Pandoc output format and defaults to `md`.
The default `md` format is exported as GitHub-Flavored Markdown. For example,
using `html` creates `report.docx.html`; the default creates
`report.docx.md`.

The script scans subdirectories recursively. Existing output files are
overwritten, and files that are not recognized as supported documents are
left unchanged. If a document cannot be read or converted, the error is
reported, a dictionary-filtered `strings` extraction is saved as
`<full-filename>.txt`, and processing continues with the next file. For
example, a failed `report.docx` conversion produces `report.docx.txt`. Files
reported by `file` simply as `data` are also sent directly through this text
extraction fallback.

## Supported document types

Detection is based on `file` output and MIME types, not extensions. The
converter supports modern Word documents, legacy Word/OLE documents, RTF,
OpenDocument text files, and WordPerfect documents that LibreOffice can read.
