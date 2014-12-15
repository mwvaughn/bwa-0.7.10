# Unpack binaries. For long-term portability, it's best to
# avoid TACC modules
tar -xzf bin.tgz
export PATH=$PATH:$PWD/bin

# SPLIT_COUNT / 4 = number of records per BWA job
SPLIT_COUNT=4000000
# 8 GB
SORT_RAM=8589934592

OUTPUT=bwa_output

# Vars passed in from outside
REFERENCE=${databaseFasta}
QUERY1=${query1}
QUERY2=${query2}
CPUS=${IPLANT_CORES_REQUESTED}

ARGS="${numThreads} ${mismatchTolerance} ${maxGapOpens} ${maxGapExtensions} ${noEndIndel} ${maxOccLongDeletion} ${seedLength} ${maxDifferenceSeed} ${maxEntriesQueue} ${mismatchPenalty} ${gapOpenPenalty} ${gapExtensionPenalty} ${stopSearching} ${qualityForTrimming} ${barCodeLength} ${logScaleGapPenalty} ${nonIterativeMode} ${illuminaLike}"

# Determine pair-end or not
IS_PAIRED=0
if [[ -n "$QUERY1" && -n "$QUERY2" ]]; then let IS_PAIRED=1; echo "Paired-end"; fi

# Assume script is already running in a scratch directory
# Create subdirectories for BWA workflow
for I in input1 input2 temp
do
	echo "Creating $I"
	mkdir -p $I
done

# Split sequences, handling compressed data seamlessly without intermediate decompression
QUERY1_F=$(basename ${QUERY1})
if [[ "$QUERY1_F" =~ .fq$ ]] || [[ "$QUERY1_F" =~ .fastq$ ]] || [[ "$QUERY1_F" =~ .fasta$ ]] || [[ "$QUERY1_F" =~ .fa$ ]]; then
    split -l $SPLIT_COUNT --numeric-suffixes $QUERY1_F input1/query.
    echo "$QUERY1_F was not compressed";
elif [[ "$QUERY1_F" =~ .gz$ ]]; then
    bin/extract.sh $QUERY1_F | split -l $SPLIT_COUNT --numeric-suffixes - input1/query.
    echo "$QUERY1_F was compressed";
fi

if [[ "$IS_PAIRED" -eq 1 ]];
then
	QUERY2_F=$(basename ${QUERY2})
	if [[ "$QUERY2_F" =~ .fq$ ]] || [[ "$QUERY2_F" =~ .fastq$ ]] || [[ "$QUERY2_F" =~ .fasta$ ]] || [[ "$QUERY2_F" =~ .fa$ ]]; then
        split -l $SPLIT_COUNT --numeric-suffixes $QUERY1_F input2/query.
        echo "$QUERY2_F was not compressed";
    elif [[ "$QUERY2_F" =~ .gz$ ]]; then
        bin/extract.sh $QUERY2_F | split -l $SPLIT_COUNT --numeric-suffixes - input2/query.
        echo "$QUERY2_F was compressed";
    fi
fi

# Assumptions: Reference is a zip file containing the reference
# FASTA and associated bwa index files, the index files are tied
# to the reference FASTA name, that EXTENSION is a valid suffix
# unique to bwa index files

REFERENCE_F=$(basename ${REFERENCE})
GENOME_F_ARCHIVE=$REFERENCE_F
TARGET="reference"
EXTENSION="64.amb"
mkdir -p ${TARGET}
unzip -d ${TARGET} -q ${GENOME_F_ARCHIVE} && rm -rf ${GENOME_F_ARCHIVE}
REFERENCE_F=$(basename $(find ${TARGET}/ -name "*.${EXTENSION}" -print0) ".${EXTENSION}")
REFERENCE_F="${TARGET}/$REFERENCE_F"
echo $REFERENCE_F

# Align using the parametric launcher
# Create paramlist for initial alignment + SAI->SAM conversion
# Emit one cli if single-end, another if pair end
rm -rf paramlist.aln

for C in input1/*
do
	ROOT=$(basename $C);
	if [ "$IS_PAIRED" -eq 1 ]; then
		echo "bwa aln ${ARGS} $REFERENCE_F input1/$ROOT > temp/$ROOT.1.sai && bwa aln ${ARGS} $REFERENCE_F input2/$ROOT > temp/$ROOT.2.sai && bwa sampe $REFERENCE_F temp/$ROOT.1.sai temp/$ROOT.2.sai input1/$ROOT input2/$ROOT | samtools view -bSu - | samtools sort -m $SORT_RAM - temp/${ROOT}.sorted" >> paramlist.aln
	else
		echo "bwa aln ${ARGS} $REFERENCE_F input1/$ROOT > temp/$ROOT.1.sai && bwa samse $REFERENCE_F temp/$ROOT.1.sai input1/$ROOT | samtools view -bSu - | samtools sort -m $SORT_RAM - temp/${ROOT}.sorted" >> paramlist.aln
	fi
done

echo "Launcher...."
date
export TACC_LAUNCHER_SCHED=dynamic
EXECUTABLE=$TACC_LAUNCHER_DIR/init_launcher
$TACC_LAUNCHER_DIR/paramrun $EXECUTABLE paramlist.aln
date
echo "..Done"

echo "Merging sorted BAMs"
OWD=$PWD
cd temp
BAMS=`ls *.sorted.bam`
# Merge and sort
samtools merge ${OWD}/${OUTPUT}.bam ${BAMS} && samtools index ${OWD}/${OUTPUT}.bam
cd $OWD

# Clean up temp data. If not, service will copy it all back
for M in bin $QUERY1_F $QUERY2_F $REFERENCE_F $REFERENCE_F.* input1 input2 temp .launcher
do
	echo "Cleaning $M"
	rm -rf $M
done
