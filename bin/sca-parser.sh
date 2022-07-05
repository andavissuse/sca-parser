#!/bin/sh

#
# This script parses results from various sca tools then uses tool config settings
# to provide next-step guidance.
#
# Inputs: SCA tool results file
#         (optional with -o) output file listing guidance (next steps)
#
# Output: List of next steps
#

#
# functions
#
function usage() {
	echo "Usage: `basename $0` [options] <sca-tool-results-file>"
	echo "Options:"
	echo "    -d        debug"
	echo "    -o        output file"
}

function exitError() {
	echo "$1"
	rm -rf $tmpDir 2>/dev/null
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
if [ ! "$1"} ]; then
        usage
        exit 1
else
	toolResultsFile="$1"
	toolResultsPath=`dirname $toolResultsFile`
fi
[ $DEBUG ] && echo "*** DEBUG: $0: toolResultsFile: $toolResultsFile" >&2

# sca-parser conf file
curPath=`dirname "$(realpath "$0")"`
parserConfFile="/etc/sca-parser.conf"
if [ ! -r "$parserConfFile" ]; then
        parserConfFile="/usr/etc/sca-parser.conf"
        if [ ! -r "$parserConfFile" ]; then
               	parserConfFile="$curPath/../sca-parser.conf"
               	if [ ! -r "$parserConfFile" ]; then
			# do something else?
                       	exitError "No sca-parser conf file info; exiting..."
		fi
        fi
fi
[ $DEBUG ] && echo "*** DEBUG: $0: parserConfFile: $parserConfFile" >&2
source $parserConfFile
parserBinPath="$SCA_PARSER_BIN_PATH"
parserVarPath="$SCA_PARSER_VAR_PATH"
[ $DEBUG ] && echo "*** DEBUG: $0: parserBinPath: $parserBinPath, parserVarPath: $parserVarPath" >&2

# get the prio group categories by looking for *-p?-categories in tool results file
prioGroups=`grep -E "p?-categories:" $toolResultsFile | cut -d':' -f1 | rev | cut -d'-' -f2 | rev | tr '\n' ' '`
[ $DEBUG ] && echo "*** DEBUG: $0: prioGroups: $prioGroups" >&2

# Take actions
actionsTaken=""
ts=`date +%s`
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
                        mkdir -p "${actionsVarPath}/${actionName}" 2>/dev/null
                        touch "${actionsVarPath}/${actionName}/test.$ts"
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
                                mkdir -p "$parserVarPath}/${actionName}" 2>/dev/null
                                touch "${parserVarPath}/${actionName}/test.$ts"
                                actionsTaken="$actionsTaken $actionName"
                                break
                        fi
                done
        done
done

exit 0
