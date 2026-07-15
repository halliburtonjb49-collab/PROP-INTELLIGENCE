import subprocess
import sys
from pathlib import Path

def run_command(command, cwd=None):
    print(f"\n🚀 Running: {' '.join(command)}")
    # stdout=None allows you to see the real-time installation logs
    result = subprocess.run(command, check=True, cwd=cwd)
    return result

def main():
    project_root = Path(__file__).resolve().parent
    backend_dir = project_root / "python_backend"

    if not backend_dir.exists():
        raise FileNotFoundError(f"Missing backend folder at: {backend_dir}")

    # 1. Upgrade core tools safely
    print("--- Step 1: Upgrading pip, setuptools, and wheel ---")
    run_command([
        sys.executable,
        "-m",
        "pip",
        "install",
        "--upgrade",
        "pip",
        "setuptools",
        "wheel",
        "--retries",
        "5",
        "--timeout",
        "120",
    ])

    # 2. Install the same pinned dependencies used by production hosting.
    print("\n--- Step 2: Installing backend dependencies ---")
    run_command([
        sys.executable,
        "-m",
        "pip",
        "install",
        "--prefer-binary",
        "-r",
        str(project_root / "requirements.txt"),
        "--retries",
        "5",
        "--timeout",
        "120",
    ])

    # 3. Start the backend server on port 8000
    print("\n--- Step 3: Starting backend server on port 8000 ---")
    # Run from the backend folder so imports like "from schemas import ..." resolve correctly.
    run_command([
        sys.executable,
        "-m",
        "uvicorn",
        "main:app",
        "--host",
        "127.0.0.1",
        "--port",
        "8000",
        "--reload",
    ], cwd=backend_dir)

if __name__ == "__main__":
    main()
