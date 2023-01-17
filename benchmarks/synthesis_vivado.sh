#!/bin/bash
# use bash master.sh not sh master.sh
vivadoOutput="vivadoOutput"
vivadoSynResultsCSV="vivadoSynResults.csv"
powerReport="power_report.rpt"
tmp=""
vhdName=""

touch $vivadoOutput
chmod 666 $vivadoOutput
touch $vivadoSynResultsCSV
chmod 666 $vivadoSynResultsCSV
> $vivadoSynResultsCSV # clear file
> $vivadoOutput

echo "Filter;LUTS;DSPs;data path delay;Total On-Chip Power (W);Device Static (W);Dynamic (W); Clocks (dyn); Logic (dyn); Signals (dyn);i DSPs; I/0 (dyn)" > $vivadoSynResultsCSV
# no need to clear vivadoOutput since it will be overwritten

# read
filename=$1
while read line; do
	> $vivadoOutput
	echo $line | bash 2>&1 | tee -a $vivadoOutput

# formatted output for csv
	# get .vhd name fron python call

	# filter name
	tmp=`echo $line | awk '{print $5}'`
	echo -n $tmp >> $vivadoSynResultsCSV
        echo -n ";" >> $vivadoSynResultsCSV
	vhdName=$(awk '{print $5}' <<< $line)

	# LUTs
	tmp=`grep "Slice LUTs" $vivadoOutput | awk '{print $5}'`
	echo -n $tmp >> $vivadoSynResultsCSV
	echo -n ";" >> $vivadoSynResultsCSV
	# DSPs
	tmp=`grep "DSPs  " $vivadoOutput | awk '{print $4}'`
	echo -n $tmp >> $vivadoSynResultsCSV
        echo -n ";" >> $vivadoSynResultsCSV
	# Delay
	# FixIIR has other output so grep for output delay instead of Data path delay
	#if [[ "$vhdName" == "fixIIR.vhd" ]]; then
	#	tmp=`grep "output delay" $vivadoOutput | awk '{print $4}'`
	#else
		tmp=`grep "Data Path Delay" $vivadoOutput | awk '{print $4}'`
#	fi
	echo -n $tmp >> $vivadoSynResultsCSV
        echo -n ";" >> $vivadoSynResultsCSV

	# total power
	tmp=`grep "Total On-Chip Power (W)" $powerReport | awk '{print $7}'`
        echo -n $tmp >> $vivadoSynResultsCSV
        echo -n ";" >> $vivadoSynResultsCSV

	# static power
	tmp=`grep "Device Static (W)" $powerReport | awk '{print $6}'`
        echo -n $tmp >> $vivadoSynResultsCSV
        echo -n ";" >> $vivadoSynResultsCSV

	#dynamic power
        tmp=`grep "Dynamic (W)" $powerReport | awk '{print $5}'`
        echo -n $tmp >> $vivadoSynResultsCSV
        echo -n ";" >> $vivadoSynResultsCSV

	#clocks
	tmp=`grep "Clocks" $powerReport | awk '{print $4}'`
        echo -n $tmp >> $vivadoSynResultsCSV
        echo -n ";" >> $vivadoSynResultsCSV

	#slice logic
	tmp=`grep "Slice Logic" $powerReport | awk '{print $5}'`
        echo -n $tmp >> $vivadoSynResultsCSV
        echo -n ";" >> $vivadoSynResultsCSV

	#signals
	tmp=`grep "Signals" $powerReport | awk '{print $4}'`
        echo -n $tmp >> $vivadoSynResultsCSV
        echo -n ";" >> $vivadoSynResultsCSV

	#DSPs
        tmp=`grep "DSPs" $powerReport | awk '{print $4}'`
        echo -n $tmp >> $vivadoSynResultsCSV
        echo -n ";" >> $vivadoSynResultsCSV


	#I/O
        tmp=`grep "I/O            |" $powerReport | awk '{print $4}'`
        #echo -n $tmp >> $vivadoSynResultsCSV
        #echo -n ";" >> $vivadoSynResultsCSV

        echo -n $tmp >> $vivadoSynResultsCSV
	# last one with line break
        echo ";" >> $vivadoSynResultsCSV

	# delete power_report
	rm $powerReport
done < $filename
