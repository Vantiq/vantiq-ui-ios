#!/bin/sh
appledoc --project-name "VantiqUI Class" --project-company "VANTIQ, Inc." --company-id com.vantiq --keep-intermediate-files --create-html --no-create-docset --no-install-docset --no-publish-docset --output help .
rm -rf ../docs
mv help/html ../docs
