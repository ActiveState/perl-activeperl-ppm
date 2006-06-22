@echo off
rem Make it easy to run ppm from the development tree
rem without installing it first.

if "%1"=="" goto wperl

perl -Ilib bin\ppm %1 %2 %3 %4 %5 %6 %7 %8 %9
goto end

:wperl
start wperl -Ilib bin\ppm

:end