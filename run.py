import os
from app import app

if __name__ == '__main__':
    # 0.0.0.0 = écouter sur toutes les interfaces, pour être joignable depuis l'hôte
    # APP_PORT permet de configurer le port sans toucher au code (défaut 5000)
    port = int(os.environ.get('APP_PORT', 5000))
    app.run(host='0.0.0.0', port=port)