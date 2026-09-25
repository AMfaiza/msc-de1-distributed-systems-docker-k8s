# Distributed Systems: Docker & Local Kubernetes

Containerize, secure, publish and orchestrate an existing Flask application using Docker, Docker Hub and a local Kubernetes cluster (kind).

- **Starter application:** [ubc/flask-sample-app](https://github.com/ubc/flask-sample-app)
- **GitHub repository:** https://github.com/AMfaiza/msc-de1-distributed-systems-docker-k8s
- **Docker Hub image:** https://hub.docker.com/r/amfaiza/msc-de1-flask-app
- **Image and tag used for the final deployment:** `amfaiza/msc-de1-flask-app:1.0.0`

---

## 1. Objective and architecture

A small Flask REST API is containerized into a secure, non-root Docker image, published to Docker Hub, then deployed to a local `kind` Kubernetes cluster (1 control-plane + 2 workers) with 2 replicas, health probes, resource limits, a hardened security context and a NetworkPolicy.

**Application routes:**

| Method | Route | Description |
|--------|-------|-------------|
| GET | `/` | Welcome message |
| GET | `/items` | List all items |
| GET | `/items/{id}` | Get an item by its index |
| POST | `/items` | Add an item (JSON `{"name": "..."}`) |

> Items are stored **in memory**: the list resets on each container start. This is the original application's behavior (left unchanged).

---

## 2. Prerequisites

- Docker (with Docker Compose v2)
- `kind` and `kubectl`
- A Docker Hub account
- Docker Scout (bundled with Docker Desktop) for vulnerability scanning and SBOM generation

---

## 3. Run the original application (baseline)

```bash
python -m venv venv
source venv/bin/activate          # Windows: venv\Scripts\activate
pip install -r requirements.txt
APP_PORT=5001 python run.py        # http://localhost:5001
```

Test the routes (in a second terminal):

```bash
curl http://localhost:5001/
curl http://localhost:5001/items
curl -X POST http://localhost:5001/items -H "Content-Type: application/json" -d '{"name":"item1"}'
curl http://localhost:5001/items/0
```

Run the unit tests:

```bash
python -m unittest discover tests
```

> **Adaptations made to the original application:**
> - `run.py` was modified to listen on `0.0.0.0` (instead of `127.0.0.1`) via an `APP_PORT` variable, so the app is reachable from outside a container.
> - `flask-testing` was added to `requirements.txt` because the tests import it.
> - On macOS, port 5000 is used by AirPlay, so local execution uses `APP_PORT=5001`. Inside containers the app listens on 5000 (isolated from AirPlay).

---

## 4. Build and run the Docker image

```bash
docker build -t amfaiza/msc-de1-flask-app:1.0.0 .
docker run -d --name flask-app -p 8080:5000 amfaiza/msc-de1-flask-app:1.0.0
curl http://localhost:8080/
```

Verification:

```bash
docker ps                          # STATUS: Up ... (healthy)
docker logs flask-app              # Running on http://0.0.0.0:5000
docker exec flask-app id           # uid=10001(appuser) — non-root proof
docker images amfaiza/msc-de1-flask-app:1.0.0   # image size
docker history amfaiza/msc-de1-flask-app:1.0.0  # layers
```

Clean stop:

```bash
docker rm -f flask-app
```

---

## 5. Run with Docker Compose

```bash
docker compose up -d
docker compose ps                  # STATUS: Up ... (healthy)
curl http://localhost:8080/
docker compose down
```

The `compose.yaml` file includes: port mapping `8080:5000`, `APP_PORT` variable (no secrets), `unless-stopped` restart policy, health check, and security hardening (`no-new-privileges`, `cap_drop: ALL`, `read_only`, `tmpfs /tmp`).

---

## 6. Security: vulnerability scan and SBOM

```bash
# Vulnerability scan (Docker Scout)
docker scout cves amfaiza/msc-de1-flask-app:1.0.0 | tee security/vulnerability-scan.txt

# SBOM in SPDX format
docker scout sbom --format spdx --output security/sbom.spdx.json amfaiza/msc-de1-flask-app:1.0.0
```

**Scan result:** 0 Critical, 2 High, 7 Medium, 43 Low. The 2 High vulnerabilities (perl, zlib) come from the Debian base image and are marked `not fixed` (no upstream patch available). See the Security section of the report for the detailed analysis.

---

## 7. Publish to Docker Hub

```bash
docker tag amfaiza/msc-de1-flask-app:1.0.0 amfaiza/msc-de1-flask-app:latest
docker login -u amfaiza
docker push amfaiza/msc-de1-flask-app:1.0.0
docker push amfaiza/msc-de1-flask-app:latest

# Verification from a clean state
docker rmi amfaiza/msc-de1-flask-app:1.0.0
docker pull amfaiza/msc-de1-flask-app:1.0.0
docker run -d --name flask-app -p 8080:5000 amfaiza/msc-de1-flask-app:1.0.0
curl http://localhost:8080/
```

Published tags: `1.0.0`, `latest` (and `1.1.0` for the rolling update demonstration).

---

## 8. Create the Kubernetes cluster (kind)

```bash
kind create cluster --config kind/kind-config.yaml
kubectl get nodes                  # 1 control-plane + 2 workers, all Ready
```

---

## 9. Deploy the Kubernetes manifests

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/network-policy.yaml

kubectl get pods -n msc-de1-project -o wide    # 2 pods Running, spread across workers
kubectl get svc -n msc-de1-project
kubectl get networkpolicy -n msc-de1-project
```

The `deployment.yaml` defines: 2 replicas, Docker Hub image, port 5000, readiness + liveness probes, CPU and memory requests/limits, a controlled rolling update strategy, and a security context (`runAsNonRoot`, `runAsUser: 10001`, `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true`, `capabilities: drop ALL`, `seccompProfile: RuntimeDefault`).

---

## 10. Access and test the application

```bash
kubectl port-forward -n msc-de1-project svc/flask-app 8080:80
# In a second terminal:
curl http://localhost:8080/
curl -X POST http://localhost:8080/items -H "Content-Type: application/json" -d '{"name":"k8s-item"}'
curl http://localhost:8080/items
```

---

## 11. Distributed systems demonstrations

```bash
# A. Self-healing: delete a pod, Kubernetes recreates it
kubectl delete pod <pod-name> -n msc-de1-project
kubectl get pods -n msc-de1-project

# B. Scaling: 2 -> 3 -> 2 replicas
kubectl scale deployment/flask-app --replicas=3 -n msc-de1-project
kubectl get pods -n msc-de1-project
kubectl scale deployment/flask-app --replicas=2 -n msc-de1-project

# C. Rolling update to v1.1.0
kubectl set image deployment/flask-app flask-app=amfaiza/msc-de1-flask-app:1.1.0 -n msc-de1-project
kubectl rollout status deployment/flask-app -n msc-de1-project

# D. History and rollback to the previous revision
kubectl rollout history deployment/flask-app -n msc-de1-project
kubectl rollout undo deployment/flask-app -n msc-de1-project
kubectl rollout status deployment/flask-app -n msc-de1-project
```

---

## 12. Clean up the cluster

```bash
kind delete cluster --name msc-de1-cluster
```

---

## Security decisions and known limitations

- **Non-root execution:** dedicated user/group (UID/GID 10001) in the image, Compose and Kubernetes.
- **Hardening:** `no-new-privileges`, all Linux capabilities dropped, read-only root filesystem (with a `tmpfs` / `emptyDir` for `/tmp`), `seccompProfile: RuntimeDefault`.
- **Resources:** CPU/memory requests and limits set to prevent unlimited consumption.
- **Secrets:** no secrets in the image, layers or Git; the Docker Hub token is never committed (protected by `.gitignore`). A Kubernetes Secret template is provided with no real value.
- **NetworkPolicy:** the policy documents the intended network access (ingress on port 5000, DNS egress). **Limitation:** kind's default CNI (kindnet) does not enforce NetworkPolicies; strict enforcement would require installing a compatible CNI such as Calico or Cilium.
- **Vulnerabilities:** the 2 remaining High findings are in the Debian base image and have no available fix (`not fixed`).
