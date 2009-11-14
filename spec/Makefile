PERL = perl
PPM = ppm
T_M = Text::Markdown

BE = business-edition
HTML = $(BE)-take1.html $(BE)-take2.html $(BE)-take3.html

.SUFFIXES: .txt .html
.PHONY: install_modules clean

.txt.html:
	$(PERL) -M$(T_M)=markdown -MActiveState::Handy=file_content -e 'file_content(qq($@), file_content(qq(tmpl/header.html)) . markdown(file_content(qq($<)) . file_content(qq(tmpl/footer.html))))'

all: install_modules $(HTML)

install_modules:
	@$(PERL) -M$(T_M) -e1 2>/dev/null || $(PPM) install $(T_M)

clean:
	$(PERL) -e 'unlink @ARGV' $(HTML)
