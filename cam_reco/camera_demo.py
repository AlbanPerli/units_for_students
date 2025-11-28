import cv2
import base64
import threading
import requests
import tkinter as tk
from tkinter import ttk, messagebox, scrolledtext
from PIL import Image, ImageTk


def send_chat_completion_request(base_url: str, instruction: str, image_base64_url: str) -> str:
    """
    Envoie la requête /v1/chat/completions au serveur et renvoie le texte de réponse.
    """
    url = base_url.rstrip("/") + "/v1/chat/completions"

    payload = {
        "max_tokens": 100,
        "messages": [
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": instruction},
                    {"type": "image_url", "image_url": {"url": image_base64_url}},
                ],
            }
        ],
    }

    headers = {"Content-Type": "application/json"}

    resp = requests.post(url, json=payload, headers=headers, timeout=60)
    if not resp.ok:
        raise Exception(f"Server error: {resp.status_code} - {resp.text}")

    data = resp.json()
    return data["choices"][0]["message"]["content"]


class CameraApp:
    def __init__(self, root: tk.Tk):
        self.root = root
        self.root.title("Camera Interaction App (Python/OpenCV)")

        # Variables d'état
        self.cap = None
        self.current_frame = None
        self.is_processing = False
        self.is_request_in_flight = False

        # Variables Tk
        self.base_url_var = tk.StringVar(value="http://localhost:8080")
        self.instruction_var = tk.StringVar(value="What do you see?")
        self.interval_var = tk.StringVar(value="500")  # ms

        # Construction UI
        self.build_ui()

        # Initialisation de la caméra
        self.init_camera()

        # Boucle d'update de la vidéo
        self.update_frame()

        # Gestion de la fermeture
        self.root.protocol("WM_DELETE_WINDOW", self.on_close)

    # --------- UI ---------
    def build_ui(self):
        # Frame vidéo (prend toute la largeur, peut s'étendre)
        video_frame = tk.Frame(self.root)
        video_frame.pack(padx=10, pady=10, fill="both", expand=True)

        self.video_label = tk.Label(
            video_frame,
            text="Initialisation de la caméra...",
            bg="black",
            fg="white",
            anchor="center",
        )
        self.video_label.pack(fill="both", expand=True)

        # Zone IO (base URL, instruction, réponse)
        io_frame = tk.Frame(self.root)
        io_frame.pack(padx=10, pady=10, fill="x")

        # Base URL
        base_frame = tk.Frame(io_frame)
        base_frame.pack(side="top", fill="x", pady=5)
        tk.Label(base_frame, text="Base API:").pack(anchor="w")
        tk.Entry(base_frame, textvariable=self.base_url_var, width=60).pack(
            anchor="w", fill="x"
        )

        # Instruction
        instr_frame = tk.Frame(io_frame)
        instr_frame.pack(side="top", fill="x", pady=5)
        tk.Label(instr_frame, text="Instruction:").pack(anchor="w")
        self.instruction_entry = tk.Entry(instr_frame, textvariable=self.instruction_var, width=80)
        self.instruction_entry.pack(anchor="w", fill="x")

        # Réponse
        resp_frame = tk.Frame(io_frame)
        resp_frame.pack(side="top", fill="x", pady=5)
        tk.Label(resp_frame, text="Response:").pack(anchor="w")
        self.response_text = scrolledtext.ScrolledText(resp_frame, height=3, width=80)
        self.response_text.pack(anchor="w", fill="x")
        self.response_text.insert("1.0", "Camera initialisation...")
        self.response_text.config(state="disabled")

        # Contrôles (intervalle, start/stop)
        controls_frame = tk.Frame(self.root)
        controls_frame.pack(padx=10, pady=10)

        tk.Label(controls_frame, text="Interval between 2 requests:").pack(side="left")

        self.interval_combo = ttk.Combobox(
            controls_frame,
            textvariable=self.interval_var,
            values=["100", "250", "500", "1000", "2000"],
            width=8,
            state="readonly",
        )
        self.interval_combo.pack(side="left", padx=5)

        self.start_button = tk.Button(
            controls_frame,
            text="Start",
            command=self.toggle_start_stop,
            bg="#28a745",
            fg="white",
            width=10,
        )
        self.start_button.pack(side="left", padx=10)

    # --------- Caméra ---------
    def init_camera(self):
        # Sur Mac, tu peux essayer AVFOUNDATION si besoin :
        # self.cap = cv2.VideoCapture(0, cv2.CAP_AVFOUNDATION)
        self.cap = cv2.VideoCapture(0)

        # Demande une résolution 1280x720 (si supportée)
        if self.cap is not None and self.cap.isOpened():
            self.cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
            self.cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)

        if not self.cap.isOpened():
            self.update_response(
                "Error accessing camera. "
                "Assurez-vous qu'elle n'est pas utilisée ailleurs et que les permissions sont accordées."
            )
            messagebox.showerror("Camera error", "Impossible d'accéder à la caméra.")
        else:
            self.update_response("Camera access granted. Ready to start.")

    def update_frame(self):
        """
        Lit une frame de la caméra et l'affiche dans le Label Tkinter.
        """
        if self.cap is not None and self.cap.isOpened():
            ret, frame = self.cap.read()
            if ret:
                self.current_frame = frame

                # Conversion BGR -> RGB
                frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                img = Image.fromarray(frame_rgb)

                # Affichage en grand (1280x720)
                img = img.resize((800, 500))
                imgtk = ImageTk.PhotoImage(image=img)

                # Tkinter doit garder une ref
                self.video_label.imgtk = imgtk
                self.video_label.configure(image=imgtk, text="")

        # Planifie l'appel suivant
        self.root.after(30, self.update_frame)

    # --------- Start / Stop ---------
    def toggle_start_stop(self):
        if self.is_processing:
            self.handle_stop()
        else:
            self.handle_start()

    def handle_start(self):
        if self.cap is None or not self.cap.isOpened():
            self.update_response("Camera not available. Cannot start.")
            messagebox.showwarning(
                "Camera", "Camera not available. Please check permissions."
            )
            return

        self.is_processing = True
        self.start_button.config(text="Stop", bg="#dc3545")

        self.instruction_entry.config(state="disabled")
        self.interval_combo.config(state="disabled")

        self.update_response("Processing started...")

        # premier envoi immédiat
        self.send_data()

    def handle_stop(self):
        self.is_processing = False
        self.start_button.config(text="Start", bg="#28a745")
        self.instruction_entry.config(state="normal")
        self.interval_combo.config(state="readonly")

        if self.get_response_text().startswith("Processing started..."):
            self.update_response("Processing stopped.")

    # --------- Envoi des données ---------
    def schedule_next_request(self, delay_ms=None):
        if not self.is_processing:
            return
        if delay_ms is None:
            delay_ms = int(self.interval_var.get())
        self.root.after(delay_ms, self.send_data)

    def send_data(self):
        if not self.is_processing:
            return

        # Empêcher le chevauchement de requêtes
        if self.is_request_in_flight:
            self.schedule_next_request()
            return

        frame = self.current_frame
        if frame is None:
            self.update_response("Failed to capture image. Stream might not be active.")
            self.schedule_next_request()
            return

        # Encodage JPEG + Base64
        success, buffer = cv2.imencode(".jpg", frame, [int(cv2.IMWRITE_JPEG_QUALITY), 80])
        if not success:
            self.update_response("Failed to encode image.")
            self.schedule_next_request()
            return

        jpg_bytes = buffer.tobytes()
        b64_str = base64.b64encode(jpg_bytes).decode("ascii")
        image_data_url = f"data:image/jpeg;base64,{b64_str}"

        instruction = self.instruction_var.get()
        base_url = self.base_url_var.get().strip()

        # Lancer la requête dans un thread pour ne pas bloquer l'UI
        self.is_request_in_flight = True

        def worker():
            try:
                response = send_chat_completion_request(base_url, instruction, image_data_url)
            except Exception as e:
                response = f"Error: {e}"
            self.root.after(0, lambda: self.on_response(response))

        threading.Thread(target=worker, daemon=True).start()

        # Programme le prochain envoi
        self.schedule_next_request()

    def on_response(self, text: str):
        self.is_request_in_flight = False
        self.update_response(text)

    # --------- Helpers UI ---------
    def update_response(self, text: str):
        self.response_text.config(state="normal")
        self.response_text.delete("1.0", tk.END)
        self.response_text.insert(tk.END, text)
        self.response_text.config(state="disabled")

    def get_response_text(self) -> str:
        return self.response_text.get("1.0", tk.END).strip()

    # --------- Fermeture ---------
    def on_close(self):
        self.is_processing = False
        if self.cap is not None and self.cap.isOpened():
            self.cap.release()
        self.root.destroy()


if __name__ == "__main__":
    root = tk.Tk()
    # Taille initiale confortable
    root.geometry("1400x900")
    app = CameraApp(root)
    root.mainloop()