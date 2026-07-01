@echo off
cd /d "%~dp0"
title portable.sn - serveur local (ne pas fermer)
echo ============================================
echo   portable.sn - serveur local demarre
echo.
echo   Boutique : http://localhost:5050/
echo   Admin    : http://localhost:5050/admin.html
echo.
echo   Laisse cette fenetre OUVERTE pendant l'utilisation.
echo   Ferme-la pour arreter le serveur.
echo ============================================
echo.
start "" http://localhost:5050/admin.html
npx --yes http-server -p 5050 -c-1
