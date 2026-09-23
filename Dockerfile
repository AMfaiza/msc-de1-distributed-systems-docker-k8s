# syntax=docker/dockerfile:1

# Image de base : Python 3.12 en version "slim" (allégée)
FROM python:3.12-slim AS runtime

# Variables d'environnement pour un comportement propre en conteneur
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    APP_PORT=5000

# Crée un utilisateur et un groupe non-root (UID/GID fixés à 10001)
RUN groupadd --gid 10001 appgroup \
    && useradd --uid 10001 --gid 10001 --no-create-home --shell /usr/sbin/nologin appuser

# Dossier de travail dans le conteneur
WORKDIR /app

# Copie d'abord le fichier des dépendances (pour profiter du cache Docker)
COPY requirements.txt .

# Installe les dépendances sans cache, puis ajoute curl (pour le healthcheck)
RUN pip install --no-cache-dir -r requirements.txt \
    && apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

# Copie uniquement ce qui est nécessaire à l'exécution
COPY app/ ./app/
COPY run.py .

# Bascule sur l'utilisateur non-root
USER 10001:10001

# Déclare le port utilisé par l'application
EXPOSE 5000

# Vérification de santé au niveau Docker
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:5000/ || exit 1

# Commande de démarrage (forme exec pour bien recevoir les signaux d'arrêt)
CMD ["python", "run.py"]