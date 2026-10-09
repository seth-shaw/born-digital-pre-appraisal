# Document Converter

This project builds a Docker image containing Apache Tika Server 4.x. The
container starts one local Tika server, waits for it to become ready, warms up
its parser worker, and then recursively extracts each file's content as HTML
through the REST API. The server is reused for the entire batch so Java and
parser startup do not recur for every file.

Tika detects formats from file content rather than relying on filename
extensions. The image currently pins Apache Tika 4.1.0 and verifies the
downloaded server distribution with its published SHA-512 checksum. The server
listens only on the container's loopback interface and stops when conversion
finishes.

The image also includes Tesseract and its English language data. Tika is
configured to use Tesseract as its text recognizer for supported raster images
and for scanned PDF pages that need OCR under Tika's default automatic policy.

## Build the image

From this directory, run:

```sh
docker build -t doc-converter .
```

## Convert a directory

Place the documents to convert in a directory such as `./documents`, then run
the container with that directory mounted at `/work/input`.

### PowerShell

```powershell
docker run --rm `
  --mount "type=bind,source=${PWD}\documents,target=/work/input" `
  doc-converter /work/input
```

### Linux/macOS shell

```sh
docker run --rm \
  --mount "type=bind,source=$(pwd)/documents,target=/work/input" \
  doc-converter /work/input
```

Every successful conversion creates `<full-filename>.html`; for example,
`report.docx` produces `report.docx.html`. Existing HTML output is overwritten.
Files ending in `.html` or `.txt` are skipped so generated output and fallback
files are not treated as new input on later runs.

If Tika cannot convert a file, the error is reported and a dictionary-filtered
`strings` extraction is saved as `<full-filename>.txt`. Processing then
continues with the next file.

The bundled Tika configuration maps the generic
`application/octet-stream` type to Tika's error parser. When no more-specific
parser supports a detected binary type, `/tika/html` therefore returns HTTP
422 instead of an empty successful response, allowing the converter to invoke
the text fallback.

## Supported document types

The bundled Tika standard parsers support Microsoft Office and OpenDocument
files, WordPerfect 5.x and 6.x, RTF, PDF, EPUB, iWork packages, email, text,
HTML/XML, archives, and many additional formats. Some formats expose only
metadata, and newer iWork formats may not expose body text.

## AI

Most of this repository was created using ChatGPT's Codex.
