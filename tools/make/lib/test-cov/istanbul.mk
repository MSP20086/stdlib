
# VARIABLES #

# Define the command for `node`:
NODE ?= node

# Define the command to recursively sync directories:
RSYNC_RECURSIVE ?= rsync -r

# Define the command to recursively create directories (WARNING: possible portability issues on some systems!):
MKDIR_RECURSIVE ?= mkdir -p

# Define the command for setting executable permissions:
MAKE_EXECUTABLE ?= chmod +x

# Define the command for removing files and directories:
DELETE ?= -rm
DELETE_FLAGS ?= -rf

# Determine the host kernel:
KERNEL ?= $(shell uname -s)

# Based on the kernel, determine the `open` command:
ifeq ($(KERNEL), Darwin)
	OPEN ?= open
else
	OPEN ?= xdg-open
endif
# TODO: add Windows command

# On Mac OSX, in order to use `|` and other regular expression operators, we need to use enhanced regular expression syntax (-E); see https://developer.apple.com/library/mac/documentation/Darwin/Reference/ManPages/man7/re_format.7.html#//apple_ref/doc/man/7/re_format.

ifeq ($(KERNEL), Darwin)
	find_kernel_prefix := -E
else
	find_kernel_prefix :=
endif

# Define command-line flags for finding test directories for instrumented source code:
FIND_ISTANBUL_TEST_DIRS_FLAGS ?= \
	-type d \
	-name "$(TESTS_FOLDER)" \
	-regex "$(TESTS_FILTER)"

ifneq ($(KERNEL), Darwin)
	FIND_ISTANBUL_TEST_DIRS_FLAGS := -regextype posix-extended $(FIND_ISTANBUL_TEST_DIRS_FLAGS)
endif

# Define the path to the `tap-spec` executable:
TAP_REPORTER ?= $(BIN_DIR)/tap-spec

# Define the executable for generating a coverage report name:
COVERAGE_REPORT_NAME ?= $(TOOLS_DIR)/test-cov/scripts/coverage_report_name

# Define the path to the Istanbul executable.
#
# To install Istanbul:
#     $ npm install istanbul
#
# [1]: https://github.com/gotwarlost/istanbul

ISTANBUL ?= $(BIN_DIR)/istanbul

# Define which files and directories to exclude from coverage instrumentation:
ISTANBUL_EXCLUDES_FLAGS ?= \
	--no-default-excludes \
	-x 'node_modules/**' \
	-x 'reports/**' \
	-x 'tmp/**' \
	-x "**/$(TESTS_FOLDER)/**" \
	-x "**/$(EXAMPLES_FOLDER)/**" \
	-x "**/$(BENCHMARKS_FOLDER)/**" \
	-x "**/$(CONFIG_FOLDER)/**" \
	-x "**/$(DOCUMENTATION_FOLDER)/**"

# Define which files and directories to exclude when syncing the instrumented source code directory:
ISTANBUL_RSYNC_EXCLUDES_FLAGS ?= \
	--ignore-existing \
	--exclude "$(EXAMPLES_FOLDER)/" \
	--exclude "$(BENCHMARKS_FOLDER)/" \
	--exclude "$(DOCUMENTATION_FOLDER)/"

# Define the command to instrument source code for code coverage:
ISTANBUL_INSTRUMENT ?= $(ISTANBUL) instrument

# Define the output directory for instrumented source code:
ISTANBUL_INSTRUMENT_OUT ?= $(COVERAGE_INSTRUMENTATION_DIR)/node_modules

# Define the command-line options to be used when instrumenting source code:
ISTANBUL_INSTRUMENT_FLAGS ?= \
	$(ISTANBUL_EXCLUDES_FLAGS) \
	--output $(ISTANBUL_INSTRUMENT_OUT)

# Define the command to generate test coverage:
ISTANBUL_COVER ?= $(ISTANBUL) cover

# Define the type of report Istanbul should produce:
ISTANBUL_COVER_REPORT_FORMAT ?= lcov

# Define the output file path for the HTML report generated by Istanbul:
ISTANBUL_HTML_REPORT ?= $(COVERAGE_DIR)/lcov-report/index.html

# Define the output file path for the JSON report generated by Istanbul:
ISTANBUL_JSON_REPORT ?= $(COVERAGE_DIR)/coverage.json

# Define the command-line options to be used when generating code coverage:
ISTANBUL_COVER_FLAGS ?= \
	$(ISTANBUL_EXCLUDES_FLAGS) \
	--dir $(COVERAGE_DIR) \
	--report $(ISTANBUL_COVER_REPORT_FORMAT)

# Define the command to generate test coverage reports:
ISTANBUL_REPORT ?= $(ISTANBUL) report

# Define the test coverage report format:
ISTANBUL_REPORT_FORMAT ?= lcov

# Define the command-line options to be used when generating a code coverage report:
ISTANBUL_REPORT_FLAGS ?= \
	--root $(COVERAGE_DIR) \
	--dir $(COVERAGE_DIR) \
	--include '**/coverage*.json'

# Define the test runner executable for Istanbul instrumented source code:
ifeq ($(JAVASCRIPT_TEST_RUNNER), tape)
	ISTANBUL_TEST_RUNNER ?= $(NODE) $(TOOLS_DIR)/test-cov/tape-istanbul/bin/cli
	ISTANBUL_TEST_RUNNER_FLAGS ?= \
		--dir $(ISTANBUL_INSTRUMENT_OUT) \
		--global '__coverage__'
endif


# FUNCTIONS #

# Macro to retrieve a list of test directories for Istanbul instrumented source code.
#
# $(call get-istanbul-test-dirs)

get-istanbul-test-dirs = $(shell find $(find_kernel_prefix) $(ISTANBUL_INSTRUMENT_OUT) $(FIND_ISTANBUL_TEST_DIRS_FLAGS))


# TARGETS #

# Instruments source code.
#
# This target instruments source code.

test-istanbul-instrument: $(NODE_MODULES) clean-istanbul-instrument
	$(QUIET) $(MKDIR_RECURSIVE) $(ISTANBUL_INSTRUMENT_OUT)
	$(QUIET) $(ISTANBUL_INSTRUMENT) $(ISTANBUL_INSTRUMENT_FLAGS) $(SRC_DIR)
	$(QUIET) $(RSYNC_RECURSIVE) \
		$(ISTANBUL_RSYNC_EXCLUDES_FLAGS) \
		$(SRC_DIR)/ \
		$(ISTANBUL_INSTRUMENT_OUT)

.PHONY: test-istanbul-instrument


# Run unit tests and generate a test coverage report.
#
# This target instruments source code, runs unit tests, and outputs a test coverage report.

test-istanbul: $(NODE_MODULES) test-istanbul-instrument
	$(QUIET) $(MKDIR_RECURSIVE) $(COVERAGE_DIR)
	$(QUIET) $(MAKE_EXECUTABLE) $(COVERAGE_REPORT_NAME)
	$(QUIET) for dir in $(get-istanbul-test-dirs); do \
		echo ''; \
		echo "Running tests in directory: $$dir"; \
		echo ''; \
		NODE_ENV=$(NODE_ENV_TEST) \
		NODE_PATH=$(NODE_PATH_TEST) \
		TEST_MODE=coverage \
		$(ISTANBUL_TEST_RUNNER) \
			$(ISTANBUL_TEST_RUNNER_FLAGS) \
			--output $$($(COVERAGE_REPORT_NAME) $(ISTANBUL_INSTRUMENT_OUT) $$dir $(COVERAGE_DIR)) \
			"$$dir/**/$(TESTS_PATTERN)" \
		| $(TAP_REPORTER) || exit 1; \
	done
	$(QUIET) $(MAKE) -f $(this_file) test-istanbul-report

.PHONY: test-istanbul


# Generate a test coverage report.
#
# This target generates a test coverage report from JSON coverage files.

test-istanbul-report: $(NODE_MODULES)
	$(QUIET) $(ISTANBUL_REPORT) $(ISTANBUL_REPORT_FLAGS) $(ISTANBUL_REPORT_FORMAT)

.PHONY: test-istanbul-report


# Run unit tests and generate a test coverage report.
#
# This target instruments source code, runs unit tests, and outputs a test coverage report.

test-istanbul-cover: $(NODE_MODULES)
	$(QUIET) NODE_ENV=$(NODE_ENV_TEST) \
	NODE_PATH=$(NODE_PATH_TEST) \
	$(ISTANBUL_COVER) $(ISTANBUL_COVER_FLAGS) $(JAVASCRIPT_TEST) -- $(JAVASCRIPT_TEST_FLAGS) $(TESTS)

.PHONY: test-istanbul-cover


# View a test coverage report.
#
# This target opens an HTML coverage report in a local web browser.

view-istanbul-report:
	$(QUIET) $(OPEN) $(ISTANBUL_HTML_REPORT)

.PHONY: view-istanbul-report


# Removes instrumented files.
#
# This targets removes previously instrumented files by removing the instrumented source code directory entirely.

clean-istanbul-instrument:
	$(QUIET) $(DELETE) $(DELETE_FLAGS) $(COVERAGE_INSTRUMENTATION_DIR)

.PHONY: clean-istanbul-instrument
