UNAME = $(shell uname)
CYGW  = $(findstring CYGWIN, $(UNAME))
export CYGW

ERL_VER  = 6.3
ERTS_VER = 6.3

ifeq ($(CYGW), CYGWIN)
    RELEASE = windows-release
    LOCAL_RELEASE  = windows-local-release
    export REBAR = rebar.cmd
    export ERL     = /cygdrive/c/Program\ Files/erl6.3/bin/erl -smp
    export ERLC    = /cygdrive/c/Program\ Files/erl6.3/bin/erlc -Werror
    export ERLCY   = /cygdrive/c/Program\ Files/erl6.3/bin/erlc
    export ASNC    = /cygdrive/c/Program\ Files/erl6.3/bin/erlc -Werror -bber
    export JAVA	   = /cygdrive/c/Program\ Files/Java/jdk1.8.0_31/bin/java.exe
    export JAVAC   = /cygdrive/c/Program\ Files/Java/jdk1.8.0_31/bin/javac.exe
    export JAVAJAR = /cygdrive/c/Program\ Files/Java/jdk1.8.0_31/bin/jar.exe
else
	export JAVA_HOME = /home/seb/src/lib/jdk8/jdk1.8.0_45
    RELEASE        = unix-release
    LOCAL_RELEASE  = unix-local-release
    export ERL     = erl
    export ERLC    = erlc -Werror
    export ERLCY   = erlc
    export ASNC    = erlc -Werror -bber
    export JAVA    = java
    export JAVAC   = javac
    export JAVAJAR = jar
endif

export MAKE        = /usr/bin/make
export REL_NAME    = sysmo
export REL_VERSION = 0.2.1
export MODS = supercast monitor errd4j snmpman sysmo nchecks equartz pping 

.PHONY: all compile test doc clean var-clean rel-clean start \
	unix-release unix-local-release windows-release windows-local-release

all: compile


compile:
	$(MAKE) -C lib

test:
	$(MAKE) -C lib test

doc:
	$(MAKE) -C lib doc

clean: var-clean crash-clean rel-clean
	rm -f pping.exe
	$(MAKE) -C lib clean

var-clean:
	rm -f lib/jars/*.jar
	rm -rf var/monitor/*/
	rm -rf var/docroot/tmp-*/
	rm -rf var/monitor/targets.dets
	rm -rf var/monitor_events
	rm -f var/snmp/snmpm_config_db
	rm -f var/log/*.log
	rm -f var/mnesia/*.LOG
	rm -f var/mnesia/*.DAT
	rm -f var/mnesia/*.DCD
	rm -f var/mnesia/*.DCL
	rm -f var/engineID.conf

crash-clean:
	rm -f erl_crash.dump
	rm -f MnesiaCore.*

rel-clean:
	rm -f $(REL_NAME).script
	rm -f $(REL_NAME).boot
	rm -f sys.config
	rm -f var/docroot/nchecks/*.xml
	rm -f $(REL_NAME).tar
	rm -f $(REL_NAME)-$(REL_VERSION).tar.gz
	rm -rf $(REL_NAME)-win32-$(REL_VERSION)

jars:
	cp lib/snmpman/java_lib/*.jar lib/jars/
	cp lib/equartz/java_lib/*.jar lib/jars/
	cp lib/nchecks/java_lib/*.jar lib/jars/
	cp lib/errd4j/java_lib/*.jar lib/jars/


######################
# RELEASES UTILITIES #
######################
MODS_EBIN_DIR      = $(addprefix ./lib/, $(addsuffix /ebin, $(MODS)))
MODS_DEF_FILE      = $(foreach app, $(MODS_EBIN_DIR), $(wildcard $(app)/*.app))
ERL_NMS_PATH       = $(addprefix -pa ,$(MODS_EBIN_DIR))
ERL_REL_COMM       = '\
    systools:make_script("$(REL_NAME)", [local]),\
    init:stop()\
'
ERL_REL_COMM2   = '\
    systools:make_script("$(REL_NAME)", []), \
    systools:make_tar("$(REL_NAME)", [{erts, code:root_dir()}]),\
    init:stop()\
'
start: rel-clean $(LOCAL_RELEASE)
	$(ERL) -sname sysmo -boot ./$(REL_NAME) -config ./sys

release: $(RELEASE)

$(REL_NAME).script: $(MODS_DEF_FILE) $(REL_NAME).rel
	@echo "Generating $(REL_NAME).script and $(REL_NAME).boot files..."
	@$(ERL) -noinput $(ERL_NMS_PATH) -eval $(ERL_REL_COMM)

TMP_DIR     = /tmp/nms_tar_dir
WIN_TMP_DIR = C:\\cygwin\\tmp\\nms_tar_dir
ERL_UNTAR   = '\
    File = "$(REL_NAME).tar", \
    erl_tar:extract(File, [{cwd, "$(WIN_TMP_DIR)"}]), \
    init:stop() \
'


##########################
# WINDOWS RELEASES BEGIN #
##########################
windows-local-release: compile $(REL_NAME).script jars
	cp lib/nchecks/priv/defs/* var/docroot/nchecks/
	cp lib/nchecks/priv/defs/* cfg/nchecks/
	cp lib/pping/pping.exe .
	cp release_tools/sys.config.base ./sys.config
	chmod -w sys.config

windows-release: var-clean rel-clean compile jars
	@echo "Generating $(REL_NAME)-win32-$(REL_VERSION) release: ."
	$(ERL) -noinput $(ERL_NMS_PATH) -eval $(ERL_REL_COMM2)
	rm -rf $(TMP_DIR)
	mkdir  $(TMP_DIR)
	gzip -d $(REL_NAME).tar.gz
	rm -f   $(REL_NAME).tar.gz
	$(ERL) -noinput -eval $(ERL_UNTAR)
	cp -R var $(TMP_DIR)
	cp lib/nchecks/priv/defs/* $(TMP_DIR)/var/docroot/nchecks/
	mkdir $(TMP_DIR)/nt-tools
	cp release_tools/win32/nt-*         $(TMP_DIR)/nt-tools/
	cp release_tools/win32/erl.ini.src  $(TMP_DIR)/erts-$(ERTS_VER)/bin/erl.ini.src
	cp release_tools/sys.config.base    $(TMP_DIR)/releases/$(REL_VERSION)/sys.config
	cp release_tools/sysmo.io.URL		$(TMP_DIR)/
	mkdir $(TMP_DIR)/cfg
	cp -r cfg/* $(TMP_DIR)/cfg/
	rm -f $(TMP_DIR)/cfg/users.xml
	mkdir -p $(TMP_DIR)/lib/jars
	cp lib/jars/*.jar $(TMP_DIR)/lib/jars/
	cp lib/pping/pping.exe $(TMP_DIR)/
	cp -r $(TMP_DIR) $(REL_NAME)-win32-$(REL_VERSION)
	@echo "Done!"


#######################
# UNIX RELEASES BEGIN #
#######################
unix-local-release: compile $(REL_NAME).script
	cp lib/nchecks/priv/defs/* var/docroot/nchecks/
	cp release_tools/local/sys.config.dev.unix sys.config
	chmod -w sys.config

unix-release: var-clean rel-clean compile
	@echo "Generating $(REL_NAME)-$(REL_VERSION).tar.gz"
	@$(ERL) -noinput $(ERL_NMS_PATH) -eval $(ERL_REL_COMM2)
	@rm -rf $(TMP_DIR)
	@mkdir $(TMP_DIR)
	@tar xzf $(REL_NAME).tar.gz -C $(TMP_DIR)
	@rm -f $(REL_NAME).tar.gz
	@cp -R var $(TMP_DIR)/
	@mkdir $(TMP_DIR)/bin
	@cp release_tools/unix/sysmo $(TMP_DIR)/bin/
	@cp release_tools/unix/install $(TMP_DIR)
	@cp release_tools/sys.config.src $(TMP_DIR)/releases/$(REL_VERSION)/
	@mkdir $(TMP_DIR)/cfg
	@touch $(TMP_DIR)/cfg/monitor.conf
	@tar -czf $(REL_NAME)-$(REL_VERSION).tar.gz -C $(TMP_DIR) .

