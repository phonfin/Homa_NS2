set N 2
set BUFFER 240
set K 65
set RTT 0.0001

set enableNAM 0;
set enableTraceAll 1;

set simulationTime 2.0

set startMeasurementTime 1
set stopMeasurementTime 2
set flowClassifyTime 0.001

set lineRate 1Gb
set inputLineRate 1Gb

set trace_all_name "./Homa_trace_all_[lindex $argv 0].ta";
set nam_file "./Homa_nam_[lindex $argv 0].nam";

set packetSize 1460 
set flowSize [expr 1000*$packetSize];
set flowSize_BG [expr 2000*$packetSize];

set traceSamplingInterval 0.0001
set throughputSamplingInterval 0.01

set ns [new Simulator]

Agent/TCP set packetSize_ $packetSize
Agent/TCP set window_ 2000
Agent/TCP set minrto_ 0.2 ; # minRTO = 200ms
Agent/TCP/FullTcp set interval_ 0.04 ; #delayed ACK interval = 40ms
Queue set limit_ 1000

if {$enableNAM != 0} {
	set namfile [open out.nam w]
	$ns namtrace-all $namfile
}

if {$enableTraceAll != 0} {
	set traceall [open $trace_all_name w];
	$ns trace-all $traceall;
}

set mytracefile [open mytracefile.tr w]
set throughputfile [open thrfile.tr w]

proc finish {} {
        global ns traceall enableTraceAll enableNAM namfile mytracefile throughputfile
        $ns flush-trace
        close $mytracefile
        close $throughputfile
        if {$enableNAM != 0} {
	    close $namfile
	    exec nam out.nam &
	}
	if {$enableTraceAll != 0} {
		close $traceall;
	}

	exit 0
}

proc myTrace {file} {
    global ns N traceSamplingInterval tcp qfile MainLink nbow nclient packetSize enableBumpOnWire
    
    set now [$ns now]
    
    
    $qfile instvar parrivals_ pdepartures_ pdrops_ bdepartures_
 
    puts -nonewline $file " [expr $parrivals_-$pdepartures_-$pdrops_]"    
    puts $file " $pdrops_"
     
    $ns at [expr $now+$traceSamplingInterval] "myTrace $file"
}

proc throughputTrace {file} {
    global ns throughputSamplingInterval qfile flowstats N flowClassifyTime
    
    set now [$ns now]
    
    $qfile instvar bdepartures_
    
    puts -nonewline $file "$now [expr $bdepartures_*8/$throughputSamplingInterval/1000000]"
    set bdepartures_ 0
    if {$now <= $flowClassifyTime} {
	for {set i 0} {$i < [expr $N-1]} {incr i} {
	    puts -nonewline $file " 0"
	}
	puts $file " 0"
    }

    if {$now > $flowClassifyTime} { 
	for {set i 0} {$i < [expr $N-1]} {incr i} {
	    $flowstats($i) instvar barrivals_
	    puts -nonewline $file " [expr $barrivals_*8/$throughputSamplingInterval/1000000]"
	    set barrivals_ 0
	}
	$flowstats([expr $N-1]) instvar barrivals_
	puts $file " [expr $barrivals_*8/$throughputSamplingInterval/1000000]"
	set barrivals_ 0
    }
    $ns at [expr $now+$throughputSamplingInterval] "throughputTrace $file"
}


$ns color 0 Red
$ns color 1 Orange
$ns color 2 Yellow
$ns color 3 Green
$ns color 4 Blue
$ns color 5 Violet
$ns color 6 Brown
$ns color 7 Black

for {set i 0} {$i < $N} {incr i} {
    set n($i) [$ns node]
}

set nqueue [$ns node]
set nclient [$ns node]


$nqueue color red
$nqueue shape box
$nclient color blue

for {set i 0} {$i < $N} {incr i} {
    $ns duplex-link $n($i) $nqueue $inputLineRate [expr $RTT/4] DropTail
    $ns duplex-link-op $n($i) $nqueue queuePos 0.25
}


$ns simplex-link $nqueue $nclient $lineRate [expr $RTT/4] Homa_PriQueue
$ns simplex-link $nclient $nqueue $lineRate [expr $RTT/4] Homa_PriQueue
$ns queue-limit $nqueue $nclient $BUFFER

$ns duplex-link-op $nqueue $nclient color "green"
$ns duplex-link-op $nqueue $nclient queuePos 0.25
set qfile [$ns monitor-queue $nqueue $nclient [open queue.tr w] $traceSamplingInterval]


for {set i 0} {$i < $N} {incr i} {

	set tcp($i) [new Agent/TCP/Newreno]
	set sink($i) [new Agent/TCPSink]

	$ns attach-agent $n($i) $tcp($i)
	$ns attach-agent $nclient $sink($i)
	
	$tcp($i) set fid_ [expr $i]
	$sink($i) set fid_ [expr $i]
	
	$tcp($i) set flowsize_ $flowSize;
	# this nid_ is the identifier of receivers. Make sure the flows with the same receiver have the same nid_!
	$sink($i) set nid_ 1;

	$ns connect $tcp($i) $sink($i)       
}

# $tcp(1) set flowsize_ $flowSize_BG;

for {set i 0} {$i < $N} {incr i} {
    set ftp($i) [new Application/FTP]
    $ftp($i) attach-agent $tcp($i)    
}

$ns at $traceSamplingInterval "myTrace $mytracefile"
$ns at $throughputSamplingInterval "throughputTrace $throughputfile"

set ru [new RandomVariable/Uniform]
$ru set min_ 0
$ru set max_ 1.0

for {set i 0} {$i < $N} {incr i} {
    $ns at 0.0 "$ftp($i) send 1"
#    $ns at 0.1 "$ftp($i) send $flowSize"     
}

for {set i 0} {$i < $N} {incr i} {
	$ns at 0.1 "$ftp($i) send $flowSize";
}
# $ns at 0.1 "$ftp(1) send $flowSize_BG";

set flowmon [$ns makeflowmon Fid]
set MainLink [$ns link $nqueue $nclient]

$ns attach-fmon $MainLink $flowmon

set fcl [$flowmon classifier]

$ns at $flowClassifyTime "classifyFlows"

proc classifyFlows {} {
    global N fcl flowstats
    puts "NOW CLASSIFYING FLOWS"
    for {set i 0} {$i < $N} {incr i} {
	set flowstats($i) [$fcl lookup autp 0 0 $i]
    }
} 


set startPacketCount 0
set stopPacketCount 0

proc startMeasurement {} {
global qfile startPacketCount
$qfile instvar pdepartures_   
set startPacketCount $pdepartures_
}

proc stopMeasurement {} {
global qfile startPacketCount stopPacketCount packetSize startMeasurementTime stopMeasurementTime simulationTime
$qfile instvar pdepartures_   
set stopPacketCount $pdepartures_
puts "Throughput = [expr ($stopPacketCount-$startPacketCount)/(1024.0*1024*($stopMeasurementTime-$startMeasurementTime))*$packetSize*8] Mbps"
}

#$ns at $startMeasurementTime "startMeasurement"
#$ns at $stopMeasurementTime "stopMeasurement"
                      
$ns at $simulationTime "finish"

$ns run
