#!/bin/sh

#
# This script parses results from one or more sca tool result files and takes actions
# based on settings in the tool's configuration file and sca-parser.conf.
#
# Inputs: SCA tool results file(s)
#
# Results/Outputs: Actions as described in tool and/or parser config files
#		   Record of actions taken written to <caller>.parser.<timestamp> file
#		   (or file specified with -o option}
#

#
# functions
#
function usage() {
	echo "Usage: `basename $0` [options] <sca-tool-results-file>"
	echo "Options:"
	echo "    -d	debug"
	echo "    -c	tool config file"
	echo "    -o	output file"
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
			toolConfFile="${OPTARG}"
			if [ ! -r "${toolConfFile}" ]; then
				exitError "Tool configuration file ${toolConfFile} does not exist, exiting..."
			fi
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
caller=`ps -o comm= $PPID`
ts=`date +%s`

# conf file 
parserConfFiles="/usr/etc/sca-parser.conf /etc/sca-parser.conf ${curPath}/../sca-parser.conf"
for parserConfFile in ${parserConfFiles}; do
	if [ -r "${parserConfFile}" ]; then
		found="true"
		[ $DEBUG ] && echo "*** DEBUG: $0: parserConfFile: ${parserConfFile}" >&2
		. ${parserConfFile}
	fi
done
if [ ! "${found}" ]; then
	exitError "No parser conf file info; exiting..."
fi
parserVarPath="$SCA_PARSER_VAR_PATH"
parserTmpPath="$SCA_PARSER_TMP_PATH"
[ $DEBUG ] && echo "*** DEBUG: $0: parserVarPath: $parserVarPath" >&2

# Take actions
actionsTaken=""
numToolFiles=`echo $toolResultsFiles | wc -w`
if [ $numToolFiles = 1 ]; then
	[ $DEBUG ] && echo "*** DEBUG: $0: toolResultsFile: $toolResultsFile" >&2
	if [ -z "$outFile" ]; then
		toolResultsFileDir=`dirname $toolResultsFile`
		toolResultsFileBase=`basename $toolResultsFile`
		outFile="${toolResultsFileDir}/${caller}.parser.${ts}"
	fi
	[ $DEBUG ] && echo "*** DEBUG: $0: outFile: $outFile" >&2
	prioGroups=""
	while IFS= read -r prioGroupLine; do
		[ $DEBUG ] && echo "*** DEBUG: $0: prioGroupLine: $prioGroupLine" >&2
		prioGroup=`echo $prioGroupLine | grep -i -o -E "p[0-9]" | tr '[:upper:]' '[:lower:]'`
		[ $DEBUG ] && echo "*** DEBUG: $0: prioGroup: $prioGroup" >&2
		prioGroups="$prioGroups $prioGroup"
		[ $DEBUG ] && echo "*** DEBUG: $0: prioGroups: $prioGroups" >&2
		prioCategories=`echo $prioGroupLine | cut -d"=" -f2`
		[ $DEBUG ] && echo "*** DEBUG: $0: prioCategories: $prioCategories" >&2
		prioActions=`grep -i -E "${prioGroup}_actions" $toolConfFile | cut -d"=" -f2`
		[ $DEBUG ] && echo "*** DEBUG: $0: prioActions: $prioActions" >&2
		echo "${prioGroup}-categories: $prioCategories" >> $outFile
		echo "${prioGroup}-actions: $prioActions" >> $outFile
	done < <(grep -i -E "p[0-9]_categories=" $toolConfFile)
	prioGroups=`echo $prioGroups | sed "s/^ *//" | sed "s/ *$//"`
	[ $DEBUG ] && echo "*** DEBUG: $0: prioGroups: $prioGroups" >&2
	notifyAddrs=`grep -i -E "notify_addrs=" $toolConfFile | cut -d"=" -f1 --complement`
	for prioGroup in $prioGroups; do
        	[ $DEBUG ] && echo "*** DEBUG: $0: prioGroup: $prioGroup" >&2
        	actions=`grep -i -E "${prioGroup}_actions=" $toolConfFile | cut -d"=" -f1 --complement`
        	[ $DEBUG ] && echo "*** DEBUG: $0: actions: $actions" >&2
        	for action in $actions; do
                	actionName=`echo $action | cut -d':' -f1 | sed "s/\"//g"`
                	actionDeps=`echo $action | cut -d':' -f2 | sed "s/\"//g"`
                	[ $DEBUG ] && echo "*** DEBUG: $0: actionName: $actionName, actionDeps: $actionDeps" >&2
                	if [ "$actionName" = "forward" ] && echo "$actionsTaken" | grep -q "$actionName"; then
                        	[ $DEBUG ] && echo "*** DEBUG: $0: action $actionName already taken" >&2
                        	continue
                	fi
			prioCategories=`grep -i -E "${prioGroup}_categories=" $toolConfFile | cut -d"=" -f1 --complement`
			[ $DEBUG ] && echo "*** DEBUG: $0: prioCategories: $prioCategories" >&2
                	if [ "$actionDeps" = "*" ]; then
				[ $DEBUG ] && echo "*** DEBUG: $0: taking action $actionName (no dependency on result value)" >&2
				if [ "$actionName" = "notify" ]; then
					for prioCategory in $prioCategories; do
						prioCategory=`echo $prioCategory | sed "s/\"//g"`
						[ $DEBUG ] && echo "*** DEBUG: $0: prioCategory: $prioCategory" >&2
						echo "TO: $notifyAddrs" >> ${parserVarPath}/${caller}.notify.${prioCategory}.$ts
						echo "SUBJECT: $caller Notification" >> ${parserVarPath}/${caller}.notify.${prioCategory}.$ts
						resultLine=`grep "${prioCategory}-result:" $toolResultsFile`
						if [ -z "$resultLine" ]; then
							resultLine=`grep "${prioCategory}:" $toolResultsFile`
						fi
						echo "$resultLine" >> ${parserVarPath}/${caller}.notify.${prioCategory}.$ts
						actionsTaken="$actionsTaken ${actionName}(${prioCategory})"
					done
				elif [ "$actionName" = "forward" ]; then
					touch ${parserVarPath}/${caller}/forward.$ts
					for prioCategory in $prioCategories; do
						prioCategory=`echo $prioCategory | sed "s/\"//g"`
						actionsTaken="$actionsTaken ${actionName}(${prioCategory})"
					done
				fi
                        	continue
                	fi
                	for prioCategory in $prioCategories; do
				prioCategory=`echo $prioCategory | sed "s/\"//g"`
                        	[ $DEBUG ] && echo "*** DEBUG: $0: prioCategory: $prioCategory" >&2
                        	categoryResult=`grep "${category}-result" $toolResultsFile | cut -d':' -f2 | sed "s/^ *//"`
                        	[ $DEBUG ] && echo "*** DEBUG: $0: categoryResult: $categoryResult" >&2
                        	if echo "$actionDeps" | grep -qE "^$categoryResult|,$categoryResult"; then
                                	[ $DEBUG ] && echo "*** DEBUG: $0: taking action $actionName based on category result" >&2
					if [ "$actionName" = "notify" ] && echo $actionsTaken grep -q "$actionsTaken" ; then
						echo "TO: $notifyAddrs" >> ${parserVarPath}/${caller}.notify.$ts.$i
						echo "SUBJECT: $caller Notification" >> ${parserVarPath}/${caller}.notify.$ts.$i
						grep "${prioCategory}-result:" $toolResultsFile >> ${parserVarPath}/${caller}.notify.$ts.$i
					elif [ "$actionName" = "forward" ]; then
						touch ${parserVarPath}/${caller}.forward.$ts
					fi
					actionsTaken=`echo "$actionsTaken ${actionName}(${prioCategory})" | sed "s/^ //"`
                                	break
                        	fi
                	done
        	done
	done
	echo "actionsTaken: $actionsTaken" >> $outFile
else
	[ $DEBUG ] && echo "*** DEBUG: $0: multiple tool results files"
	toolPrio="$SCA_PARSER_TOOL_PRIO"
	[ $DEBUG ] && echo "*** DEBUG: $0: toolPrio: $toolPrio" >&2
	# this is the case where taksi calls the parser with results from multiple tools (aludo, sca-L0, ...)
	# Recursively call sca-parser on each tool result based on the tool priority in sca-parser.conf
	for tool in $toolPrio; do
		for toolResultsFile in $toolResultsFiles; do
			# this will be a problem if each results file is in a separate dir...
			toolResultsFileDir=`dirname $toolResultsFile`
			if grep -q -E "^${tool}-version:" $toolResultsFile; then 
				toolConfFiles="/usr/etc/${tool}.conf /etc/${tool}.conf ${curPath}/../${tool}.conf"
				[ $DEBUG ] && echo "*** DEBUG: toolConfFiles: $toolConfFiles" >&2
				found="false"
				for toolConfFile in `tac -s ' ' <<< ${toolConfFiles}`; do
					[ $DEBUG ] && echo "*** DEBUG: $0: toolConfFile: $toolConfFile" >&2
					if [ -r "${toolConfFile}" ]; then
						found="true"
						break
					fi
				done
				if [ "$found" = "false" ]; then
					exitError "No tool conf file, exiting..." >&2
				else
					[ $DEBUG ] && ${SCA_PARSER_BIN_PATH}/sca-parser.sh "$debugOpt" -c $toolConfFile -o ${toolResultsFileDir}/${caller}.parser.${ts} $toolResultsFile ||
					${SCA_PARSER_BIN_PATH}/sca-parser.sh "$debugOpt" -c $toolConfFile -o ${toolResultsFileDir}/${caller}.${tool}.parser.${ts} $toolResultsFile
				fi
			fi	
		done
	done
fi

exit 0
