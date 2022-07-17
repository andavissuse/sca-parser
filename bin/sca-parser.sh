#!/bin/sh

#
# This script parses results from one or more sca tool result files. If only one tool
# results file is provided, the parser takes the actions as defined in the tool result
# file.  If multiple tool results files are provided, the parser takes actions as defined
# in the parser config file.
#
# Inputs: SCA tool results file(s)
#
# Outputs/Results: Actions as described in tool and/or parser config files
#

#
# functions
#
function usage() {
	echo "Usage: `basename $0` [options] <sca-tool-results-file>"
	echo "Options:"
	echo "    -d        debug"
	echo "    -o	    output file"
}

function exitError() {
        echo "$1"
        exit 1
}
 
#
# main
#

# arguments
if [ "$1" = "--help" ]; then
	usage
	exit 0
fi
while getopts 'hdo:' OPTION; do
        case $OPTION in
                h)
                        usage
			exit 0
                        ;;
                d)
                        DEBUG=1
			debugOpt="-d"
                        ;;
		o)
			outFile="${OPTARG}"
			if [ -f "${outFile}" ]; then
				exitError "Output file ${outFile} already exists, exiting..."
			fi
			if [ ! -d `dirname "${outFile}"` ]; then
				exitError "Output file path `dirname ${outFile}` does not exist, exiting..."
			fi
			;;
        esac
done
shift $((OPTIND - 1))
if [ ! "$1" ]; then
        usage
        exit 1
else
	declare -a toolResultsFiles="$@"
	for toolResultsFile in $toolResultsFiles; do
		if [ ! -r "$toolResultsFile" ]; then
			echo "Tool results file $toolResultsFile unreadable, exiting..."
			exit 1
		fi
	done
fi
[ $DEBUG ] && echo "*** DEBUG: $0: toolResultsFiles: $toolResultsFiles" >&2

curPath=`dirname "$(realpath "$0")"`
#parentPid=$PPID
#parent=`ps -o cmd= -q $PPID`
#[ $DEBUG ] && echo "*** DEBUG: $0: parent: $parent" >&2

# conf file 
parserConfFiles="/usr/etc/sca-parser.conf /etc/sca-parser.conf ${curPath}/../sca-parser.conf"
for parserConfFile in ${parserConfFiles}; do
	if [ -r "${parserConfFile}" ]; then
		found="true"
		[ $DEBUG ] && echo "*** DEBUG: $0: reading ${parserConfFile}" >&2
		. ${parserConfFile}
	fi
done
if [ ! "${found}" ]; then
	exitError "No parser conf file info; exiting..."
fi
parserVarPath="$SCA_PARSER_VAR_PATH"
toolPrio="$SCA_PARSER_TOOL_PRIO"
[ $DEBUG ] && echo "*** DEBUG: $0: parserVarPath: $parserVarPath" >&2

# Take actions
actionsTaken=""
ts=`date +%s`
numToolFiles=`echo $toolResultsFiles | wc -w`
if [ $numToolFiles = 1 ]; then
	[ $DEBUG ] && echo "*** DEBUG: $0: toolResultsFile: $toolResultsFile" >&2
	prioGroups=`grep -E "p?-categories:" $toolResultsFile | cut -d':' -f1 | rev | cut -d'-' -f2 | rev | tr '\n' ' '`
	[ $DEBUG ] && echo "*** DEBUG: $0: prioGroups: $prioGroups" >&2
	for prioGroup in $prioGroups; do
        	[ $DEBUG ] && echo "*** DEBUG: $0: prioGroup: $prioGroup" >&2
        	actions=`grep "${prioGroup}-actions:" $toolResultsFile | cut -d":" -f1 --complement`
        	[ $DEBUG ] && echo "*** DEBUG: $0: actions: $actions" >&2
        	for action in $actions; do
                	actionName=`echo $action | cut -d':' -f1`
                	actionDeps=`echo $action | cut -d':' -f2`
                	[ $DEBUG ] && echo "*** DEBUG: $0: actionName: $actionName, actionDeps: $actionDeps" >&2
                	if echo "$actionsTaken" | grep -q "$actionName"; then
                        	[ $DEBUG ] && echo "*** DEBUG: $0: action $actionName already taken" >&2
                        	continue
                	fi
                	if [ "$actionDeps" = "*" ]; then
                        	[ $DEBUG ] && echo "***  DEBUG: $0: taking action $actionName (no dependency on result)" >&2
                        	mkdir -p "${parserVarPath}/${actionName}" 2>/dev/null
                        	touch "${parserVarPath}/${actionName}/test.$ts"
                        	actionsTaken="$actionsTaken $actionName"
                        	continue
                	fi
                	categories=`grep "${prioGroup}-categories:" $toolResultsFile | cut -d":" -f2`
                	[ $DEBUG ] && echo "*** DEBUG: $0: categories: $categories" >&2
                	for category in $categories; do
                        	[ $DEBUG ] && echo "*** DEBUG: $0: category: $category" >&2
                        	categoryResult=`grep "${category}-result" $toolResultsFile | cut -d':' -f2 | sed "s/^ *//"`
                        	[ $DEBUG ] && echo "*** DEBUG: $0: categoryResult: $categoryResult" >&2
                        	if echo "$actionDeps" | grep -qE "^$categoryResult|,$categoryResult"; then
                                	[ $DEBUG ] && echo "*** DEBUG: $0: taking action $actionName based on category result" >&2
                                	mkdir -p "${parserVarPath}/${actionName}" 2>/dev/null
                                	touch "${parserVarPath}/${actionName}/test.$ts"
                                	actionsTaken=`echo "$actionsTaken $actionName" | sed "s/^ //"`
                                	break
                        	fi
                	done
        	done
	done
	echo "actionsTaken: $actionsTaken" >> $toolResultsFile
else
	[ $DEBUG ] && echo "*** DEBUG: $0: multiple tool result files"
	# what to do when taksi calls the parser?
fi

exit 0
