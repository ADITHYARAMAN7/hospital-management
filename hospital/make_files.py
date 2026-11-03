"""Generate sample medical files: medical-report.pdf + extra test reports (valid PDFs, no dependencies)."""
import os, sys, datetime

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "files")
os.makedirs(OUT, exist_ok=True)


def esc(t):
    return t.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")


def make_pdf(path, title, rows, notes):
    lines = [("F2", 20, 50, 790, "City Care Hospital"),
             ("F1", 10, 50, 772, "Department of Diagnostics  |  AWS Hospital Management System"),
             ("F2", 15, 50, 735, title)]
    y = 705
    for k, v in rows:
        lines.append(("F2", 11, 50, y, k + ":"))
        lines.append(("F1", 11, 200, y, v))
        y -= 20
    y -= 10
    lines.append(("F2", 12, 50, y, "Findings / Notes"))
    y -= 20
    for n in notes:
        lines.append(("F1", 11, 50, y, n))
        y -= 18
    lines.append(("F1", 9, 50, 60, "Generated " + datetime.datetime.now().strftime("%d-%b-%Y %H:%M") + "  -  for academic demo only"))

    stream = "0.04 0.45 0.52 rg 40 760 515 2 re f 0 0 0 rg\n"
    for font, size, x, yy, text in lines:
        stream += f"BT /{font} {size} Tf {x} {yy} Td ({esc(text)}) Tj ET\n"
    stream = stream.encode("latin-1")

    objs = [b"<< /Type /Catalog /Pages 2 0 R >>",
            b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R "
            b"/Resources << /Font << /F1 5 0 R /F2 6 0 R >> >> >>",
            b"<< /Length " + str(len(stream)).encode() + b" >>\nstream\n" + stream + b"endstream",
            b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
            b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>"]
    out = b"%PDF-1.4\n"
    offsets = []
    for i, o in enumerate(objs, 1):
        offsets.append(len(out))
        out += f"{i} 0 obj\n".encode() + o + b"\nendobj\n"
    xref = len(out)
    out += f"xref\n0 {len(objs)+1}\n0000000000 65535 f \n".encode()
    for off in offsets:
        out += f"{off:010d} 00000 n \n".encode()
    out += f"trailer\n<< /Size {len(objs)+1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
    with open(path, "wb") as f:
        f.write(out)


make_pdf(os.path.join(OUT, "medical-report.pdf"), "Medical Report",
         [("Patient ID", "P1001"), ("Patient Name", "Arjun Menon"), ("Department", "Radiology"),
          ("Appointment Date", "2026-10-21"), ("Referring Doctor", "Dr. Kavya Nair"), ("Study", "Chest X-Ray (PA view)")],
         ["Lung fields are clear. No focal consolidation.", "Cardiac silhouette within normal limits.",
          "No pleural effusion or pneumothorax.", "Impression: Normal chest radiograph."])

tests = [("test-report-blood.pdf", "Blood Test Report", "P1002", "Priya Sharma", "Pathology", ["Hemoglobin 13.6 g/dL (normal)", "WBC 7,200 /uL (normal)"]),
         ("test-report-ecg.pdf", "ECG Report", "P1003", "Rahul Verma", "Cardiology", ["Normal sinus rhythm, 76 bpm", "No ST-T changes"]),
         ("test-report-mri.pdf", "MRI Brain Report", "P1004", "Sneha Iyer", "Neurology", ["No acute infarct or haemorrhage", "Ventricles normal in size"])]
for fn, title, pid, name, dept, notes in tests:
    make_pdf(os.path.join(OUT, fn), title,
             [("Patient ID", pid), ("Patient Name", name), ("Department", dept), ("Appointment Date", "2026-10-21")], notes)

# A deliberately invalid upload (wrong type) to demonstrate the Lambda Errors metric
with open(os.path.join(OUT, "corrupted-upload.exe"), "wb") as f:
    f.write(b"MZ-not-a-medical-document")
# An empty "report" -> also rejected by the processor
open(os.path.join(OUT, "empty-report.pdf"), "wb").close()
print("files written to", OUT)
