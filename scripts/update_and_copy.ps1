#!/usr/bin/powershell
cd /HIPPEE/Framework-Scripts
git pull
cp copy_kernel.ps1 ../runonce.d
./runonce.ps1
