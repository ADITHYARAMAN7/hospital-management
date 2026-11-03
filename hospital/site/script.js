// Backend: AWS Lambda function URL (HospitalPatientAPI) -> Amazon RDS MySQL (HospitalDB)
const API_URL = "__API_URL__";

const form = document.getElementById("patientForm");
const submitBtn = document.getElementById("submitBtn");
const toast = document.getElementById("toast");
const body = document.getElementById("recordsBody");
const statusEl = document.getElementById("apiStatus");
const statusText = document.getElementById("apiStatusText");
const dateInput = document.getElementById("appointmentDate");

const today = new Date();
const isoToday = new Date(today.getTime() - today.getTimezoneOffset() * 60000).toISOString().slice(0, 10);
dateInput.min = isoToday;

let toastTimer;
function showToast(message, type = "info", ms = 5000) {
  clearTimeout(toastTimer);
  toast.className = `toast show ${type}`;
  toast.innerHTML = message;
  if (ms) toastTimer = setTimeout(() => (toast.className = "toast"), ms);
}

function setError(id, message) {
  const field = document.getElementById(id).closest(".field");
  document.getElementById(`${id}-error`).textContent = message || "";
  field.classList.toggle("invalid", Boolean(message));
}

function validate(data) {
  let ok = true;
  const rules = {
    patientId: [/^P\d{3,8}$/.test(data.patientId), "Patient ID is required, e.g. P1006"],
    patientName: [/^[A-Za-z][A-Za-z .'-]{1,99}$/.test(data.patientName), "Enter the patient's full name (letters only)"],
    department: [data.department !== "", "Please select a department"],
    appointmentDate: [data.appointmentDate !== "" && data.appointmentDate >= isoToday, "Choose today or a future date"],
  };
  for (const [id, [valid, msg]] of Object.entries(rules)) {
    setError(id, valid ? "" : msg);
    if (!valid) ok = false;
  }
  return ok;
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}

function formatDate(d) {
  const dt = new Date(`${String(d).slice(0, 10)}T00:00:00`);
  return isNaN(dt) ? d : dt.toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric" });
}

async function loadRecords(highlightId) {
  try {
    const res = await fetch(API_URL, { method: "GET" });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    statusEl.className = "status ok";
    statusText.textContent = "Connected to Amazon RDS";

    const rows = data.records || [];
    document.getElementById("statTotal").textContent = data.total ?? rows.length;
    document.getElementById("statDepts").textContent = new Set(rows.map((r) => r.Department)).size;
    document.getElementById("statToday").textContent = rows.filter((r) => String(r.CreatedAt).startsWith(new Date().toISOString().slice(0, 10))).length;

    if (!rows.length) {
      body.innerHTML = `<tr><td colspan="4" class="empty">No patient records yet – submit the form to add one.</td></tr>`;
      return;
    }
    body.innerHTML = rows.map((r) => `
      <tr class="${r.PatientID === highlightId ? "new-row" : ""}">
        <td class="pid">${escapeHtml(r.PatientID)}</td>
        <td>${escapeHtml(r.PatientName)}</td>
        <td><span class="badge">${escapeHtml(r.Department)}</span></td>
        <td>${escapeHtml(formatDate(r.AppointmentDate))}</td>
      </tr>`).join("");

    // Suggest the next free Patient ID
    const max = Math.max(1000, ...rows.map((r) => parseInt(String(r.PatientID).slice(1), 10) || 0));
    document.getElementById("patientId").placeholder = `e.g. P${max + 1}`;
  } catch (err) {
    statusEl.className = "status err";
    statusText.textContent = "Database unreachable";
    body.innerHTML = `<tr><td colspan="4" class="empty">Could not load records (${escapeHtml(err.message)}).</td></tr>`;
  }
}

form.addEventListener("submit", async (e) => {
  e.preventDefault();
  const data = Object.fromEntries(new FormData(form).entries());
  data.patientId = data.patientId.trim().toUpperCase();
  data.patientName = data.patientName.trim();
  if (!validate(data)) {
    showToast("Please correct the highlighted fields.", "error");
    return;
  }

  submitBtn.disabled = true;
  submitBtn.classList.add("loading");
  submitBtn.querySelector(".btn-label").textContent = "Saving…";
  try {
    const res = await fetch(API_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(data),
    });
    const out = await res.json().catch(() => ({}));
    if (res.ok) {
      showToast(`&#10004; <b>${escapeHtml(data.patientName)}</b> (${escapeHtml(data.patientId)}) – appointment in ${escapeHtml(data.department)} on ${escapeHtml(formatDate(data.appointmentDate))} saved to Amazon RDS.`, "success", 7000);
      form.reset();
      ["patientId", "patientName", "department", "appointmentDate"].forEach((id) => setError(id, ""));
      loadRecords(data.patientId);
    } else {
      showToast((out.errors || [`Request failed (HTTP ${res.status})`]).map(escapeHtml).join("<br>"), "error", 7000);
    }
  } catch (err) {
    showToast(`Network error – could not reach the server (${escapeHtml(err.message)}).`, "error", 7000);
  } finally {
    submitBtn.disabled = false;
    submitBtn.classList.remove("loading");
    submitBtn.querySelector(".btn-label").textContent = "Submit";
  }
});

form.addEventListener("reset", () => {
  ["patientId", "patientName", "department", "appointmentDate"].forEach((id) => setError(id, ""));
  showToast("Form cleared.", "info", 2500);
});

// Clear a field's error as soon as the user fixes it
form.querySelectorAll("input, select").forEach((el) =>
  el.addEventListener("input", () => el.closest(".field").classList.contains("invalid") && setError(el.id, ""))
);

document.getElementById("refreshBtn").addEventListener("click", () => loadRecords());
loadRecords();
