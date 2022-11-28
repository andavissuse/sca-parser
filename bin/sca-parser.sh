#!/bin/sh

#
# This script parses results from one or more sca tool result files and takes actions
# based on settings in configuration files.  If no tool-specific config files are
# found, sca-parser uses the original action info that was written into the tool's
# name:value output file.
#
# Inputs: Tool results file(s)
#
# Results/Outputs: Actions as listed in config files (or tool name:value output file)
#		   Record of actions taken written to <caller>.parser.<timestamp> file
#		       or other output file specified with -o option
#

#
# functions
#
function usage() {
	echo "Usage: `basename $0` [options] <sca-tool-results-file>"
	echo "Options:"
	echo "    -c	caller (needed to maintain single output file during recursion)"
	echo "    -d	debug"
	echo "    -o	output file (default is ${caller}.parser.{timestamp}"
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
while getopts 'hdc:o:' OPTION; do
        case $OPTION in
                h)
                        usage
			exit 0
                        ;;
                d)
                        DEBUG=1
			debugOpt="-d"
                        ;;
		c)
			caller="${OPTARG}"
			;;
		o)
			outFile="${OPTARG}"
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
if [ -z "$caller" ]; then
	caller=`ps -o comm= $PPID`
fi
[ $DEBUG ] && echo "*** DEBUG: $0: caller: $caller" >&2
ts=`date +%s`

# parser conf file 
parserConfFiles="${curPath}/../sca-parser.conf /etc/opt/sca/sca-parser.conf"
found="false"
for parserConfFile in ${parserConfFiles}; do
	if [ -r "${parserConfFile}" ]; then
		found="true"
		source ${parserConfFile}
		break
	fi
done
if [ "$found" = "false" ]; then
	exitError "No parser conf file info; exiting..."
fi
[ $DEBUG ] && echo "*** DEBUG: $0: parserConfFile: ${parserConfFile}" >&2
parserVarPath="$SCA_PARSER_VAR_PATH"
parserTmpPath="$SCA_PARSER_TMP_PATH"
[ $DEBUG ] && echo "*** DEBUG: $0: parserVarPath: $parserVarPath, parserTmpPath: $parserTmpPath" >&2

if [ -z "$outFile" ]; then
        outFile="${parserTmpPath}/${toolResultsFileDir}/${caller}.parser.${ts}"
fi
[ $DEBUG ] && echo "*** DEBUG: $0: outFile: $outFile" >&2

# Main code
actionsTaken=""
numToolFiles=`echo $toolResultsFiles | wc -w`
if [ $numToolFiles = 1 ]; then
	# this is the case where the parser is called on a single tool results file
	toolResultsFile=$toolResultsFiles
	tool=`grep "\-version:" $toolResultsFile | cut -d':' -f1 | sed "s/-version//"`
	[ $DEBUG ] && echo "*** DEBUG: $0: toolResultsFile: $toolResultsFile, tool: $tool" >&2
	if [ -z "$outFile" ]; then
		toolResultsFileDir=`dirname $toolResultsFile`
		outFile="${toolResultsFileDir}/${caller}.parser.${ts}"
	fi
	[ $DEBUG ] && echo "*** DEBUG: $0: outFile: $outFile" >&2
	# get priority info from tool conf file (fallback is to use priorities in tool results file)
	toolConfFiles="${curPath}/../${tool}.conf /etc/opt/sca/${tool}.conf"
	found="false"
	for toolConfFile in ${toolConfFiles}; do
		if [ -r "${toolConfFile}" ]; then
			found="true"
			source $toolConfFile
			break
		fi
	done
	if [ "$found" = "false" ]; then
		[ $DEBUG ] && echo "*** DEBUG: No tool conf file, using priorities in tool results file..." >&2
		toolConfFile="$toolResultsFile"
	fi
	[ $DEBUG ] && echo "*** DEBUG: $0: toolConfFile: $toolConfFile" >&2
	echo "tool: $tool" >> $outFile
	echo "toolResultsFile: $toolResultsFile" >> $outFile
	echo "toolConfFile: $toolConfFile" >> $outFile
	prioGroups=""
	while IFS= read -r prioGroupCatLine; do
		[ $DEBUG ] && echo "*** DEBUG: $0: prioGroupCatLine: $prioGroupCatLine" >&2
		prioGroupCatLine=`echo $prioGroupCatLine | tr '[:upper:]' '[:lower:]'`
		prioGroup=`echo $prioGroupCatLine | grep -o -E "p[0-9]"`
		prioGroups="$prioGroups $prioGroup"
	done < <(grep -i -E "p[0-9][_-]categories[=:]" $toolConfFile)
	prioGroups=`echo $prioGroups | sed "s/^ *//" | sed "s/ *$//"`
	[ $DEBUG ] && echo "*** DEBUG: $0: prioGroups: $prioGroups" >&2

	# take and record actions
	for prioGroup in $prioGroups; do
		categories=`grep -i -E "${prioGroup}[_-]categories[=:]" $toolConfFile`
		categories=`echo $categories | tr '[:upper:]' '[:lower:]'`
		categories=`echo $categories | sed "s/^.*${prioGroup}[_-]categories[=:]//"`
		categories=`echo $categories | sed "s/^ *//" | sed "s/\"//g"`
        	actions=`grep -i -E "${prioGroup}[_-]actions[=:]" $toolConfFile`
		actions=`echo $actions | tr '[:upper:]' '[:lower:]'`
		actions=`echo $actions | sed "s/^.*${prioGroup}[_-]actions[=:]//"`
		actions=`echo $actions | sed "s/^ *//" | sed "s/\"//g"`
		if [ -z "$categories" ] || [ -z "$actions" ]; then
			continue
		fi
        	[ $DEBUG ] && echo "*** DEBUG: $0: prioGroup: $prioGroup, categories: $categories, actions: $actions" >&2
        	for action in $actions; do
                	actionName=`echo $action | cut -d':' -f1 | sed "s/\"//g"`
                	actionDeps=`echo $action | cut -d':' -f2 | sed "s/\"//g"`
                	[ $DEBUG ] && echo "*** DEBUG: $0: actionName: $actionName, actionDeps: $actionDeps" >&2
                	if [ "$actionDeps" = "*" ]; then
				for category in $categories; do
					[ $DEBUG ] && echo "*** DEBUG: $0: category: $category" >&2
					if echo $actionsTaken | grep "${actionName}(${category})"; then
						continue
					fi
					[ $DEBUG ] && echo "*** DEBUG: $0: Taking action $actionName for $category, no dependency on $category result" >&2
					category=`echo $category | sed "s/\"//g"`
					if [ "$actionName" = "notify" ]; then
						echo "TO: $notifyAddrs" >> ${parserVarPath}/${caller}.notify.${category}.$ts
						echo "SUBJECT: $caller Notification" >> ${parserVarPath}/${caller}.notify.${category}.$ts
						resultLine=`grep "${category}-result:" $toolResultsFile`
						if [ -z "$resultLine" ]; then
							resultLine=`grep "${category}:" $toolResultsFile`
						fi
						echo "$resultLine" >> ${parserVarPath}/${caller}.notify.${category}.$ts
						actionsTaken="$actionsTaken ${actionName}(${category})"
					elif [ "$actionName" = "forward" ]; then
						if ! echo $actionsTaken | grep "forward"; then
							touch ${parserVarPath}/${caller}.forward.$ts
						fi
						category=`echo $category | sed "s/\"//g"`
						actionsTaken="$actionsTaken ${actionName}(${category})"
					fi	
				done	
			else
				for category in $categories; do
					category=`echo $category | sed "s/\"//g"`
                        		categoryResult=`grep "${category}-result" $toolResultsFile | cut -d':' -f2 | sed "s/^ *//"`
                        		[ $DEBUG ] && echo "*** DEBUG: $0: category: $category, categoryResult: $categoryResult" >&2
					for actionDep in `echo $actionDeps | tr ',' ' '`; do
						[ $DEBUG ] && echo "*** DEBUG: $0: actionDep: $actionDep" >&2
						if [ "$actionDep" = "$categoryResult" ]; then
                                			[ $DEBUG ] && echo "*** DEBUG: $0: Taking action $actionName based on category result" >&2
							if [ "$actionName" = "notify" ]; then
								echo "TO: $notifyAddrs" >> ${parserVarPath}/${caller}.notify.$ts.$i
								echo "SUBJECT: $caller Notification" >> ${parserVarPath}/${caller}.notify.$ts.$i
								grep "${category}-result:" $toolResultsFile >> ${parserVarPath}/${caller}.notify.$ts.$i
							elif [ "$actionName" = "forward" ]; then
								touch ${parserVarPath}/${caller}.forward.$ts
							fi
							actionsTaken=`echo "$actionsTaken ${actionName}(${category})" | sed "s/^ //"`
                                			break
                        			fi
					done
                		done
			fi
        	done
	done
	echo "actionsTaken: $actionsTaken" >> $outFile
else
	# this is the case where taksi calls the parser with results from multiple tools (aludo, sca-L0, ...)
	# recursively call sca-parser on each tool result based on the tool priority in sca-parser.conf
	[ $DEBUG ] && echo "*** DEBUG: $0: multiple tool results files"
	toolPrio="$SCA_PARSER_TOOL_PRIO"
	[ $DEBUG ] && echo "*** DEBUG: $0: toolPrio: $toolPrio" >&2
	for tool in $toolPrio; do
		for toolResultsFile in $toolResultsFiles; do
			if grep -q -i -E "^${tool}-version:" $toolResultsFile; then 
				[ $DEBUG ] && ${SCA_PARSER_BIN_PATH}/sca-parser.sh "$debugOpt" -o $outFile $toolResultsFile ||
				${SCA_PARSER_BIN_PATH}/sca-parser.sh -c $caller -o $outFile $toolResultsFile
			fi	
		done
	done
fi

exit 0
