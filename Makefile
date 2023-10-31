# Usage:
#   make livereload PORT=<port>

# # elm make goes to stderr, which is good since stdout will be hidden later (see below)
build: index.html lib/app.js
# build: page.html style.css

lib/app.js: src/*.elm lib/
	# elm-format --yes src/
	elm make src/Main.elm --output=lib/app.js

lib/: lib/jspdf.js lib/compressor.js

lib/jspdf.js:
	mkdir -p lib/
	curl 'https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.0.0/jspdf.es.min.js' -o lib/jspdf.js
	# 2.0.0 is the latest release i could find that didnt give (babel) error after vanilla js esm import

lib/compressor.js:
	mkdir -p lib/
	curl 'https://cdnjs.cloudflare.com/ajax/libs/compressorjs/1.2.1/compressor.esm.min.js' -o lib/compressor.js

# Note that python logs are hidden.
# Also note that inner 'make' within this makefile also has stdout hidden,
#   due to nearly insuppressible noisy logs
#   (make[1]: Entering directory ... Leaving directory...)
#   so inner errors should go to stderr in order not to be hidden
.PHONY: livereload
livereload:
	@python3 -m http.server $(PORT) 2> /dev/null &
	@printf "Opening browser.\n"
	@cmd.exe /C min "http://localhost:$(PORT)/" #page.html"
	@printf "\nWatching for changes...\n"
	@find . | entr -c -s 'make 1> /dev/null; bws ping; echo pinged 1>&2' 1> /dev/null
