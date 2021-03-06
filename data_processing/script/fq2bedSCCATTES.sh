#!/bin/nash

fa_file=$1
fq_file1=$2
fq_file2=$3
star_dir=$4




## Check whether variables are enough
if [[ ! -n "$fa_file" || ! -n "$star_dir" || ! -n "$fq_file1" || ! -n "$fq_file2" ]]; then
    echo "Error: no enough variable!
This script is used to  process the data generated by scCAT-seq in 10x platform. Fastq file is needed and the output file format is BED.
Usage:
    sh $0 <genome fa file> <fastq file R1> <fastq file R2> <STAR index>
    # Caution: file in <fastq file dir> must be fastq type, not fastq.gz! Pair-end files are needed!
    "
    exit
fi

mkdir outdir/
mkdir outdir/three_prime/
mkdir outdir/three_prime/fastq
mkdir outdir/three_prime/3tail_read_with_tag/
mkdir outdir/three_prime/3tail_read_with_tag_other_strand/
mkdir outdir/three_prime/3tail_read_with_tag_other_strand_withA10_trim/
mkdir outdir/three_prime/mapping_outdir/
mkdir outdir/three_prime/final_out/
mkdir outdir/three_prime/annote/
mkdir outdir/three_prime/collapse/


cp ${fq_file1} outdir/three_prime/fastq/
cp ${fq_file2} outdir/three_prime/fastq/

filetype=${fq_file1##*.}


if [ ${filetype} = "fq" -o ${filetype} = "fastq" ]; then
        echo "unzipped"
else
        gzip -d outdir/three_prime/fastq/*
fi


## 1. Find reads with oligo(dT) primer

for i in `ls outdir/three_prime/fastq/|grep "."`
do
	cat outdir/three_prime/fastq/${i} | paste - - - - | grep -E $'\t'"GTGGTATCAACGCAGAGT[A|G|C|T][A|G|C|T][A|G|C|T][A|G|C|T][A|G|C|T][A|G|C|T][A|G|C|T][A|G|C|T]CTAAGCCTTTTT" | awk -v FS="\t" -v OFS="\n" '{print $1, $2, $3, $4}' > outdir/three_prime/3tail_read_with_tag/${i}_with_tag
done



## 2. Find R2 reads



#### Compare R1_with_tag to R2
for i in `ls outdir/three_prime/3tail_read_with_tag/ | grep "R1.fastq_with_tag$"`
do
        perl script/cmpfastq_pe.pl outdir/three_prime/3tail_read_with_tag/${i} outdir/three_prime/fastq/${i%R1*}R2.fastq
done

#### Compare R2_with_tag to R1
for i in `ls outdir/three_prime/3tail_read_with_tag/ | grep "R2.fastq_with_tag$"`
do
        perl script/cmpfastq_pe.pl outdir/three_prime/3tail_read_with_tag/${i} outdir/three_prime/fastq/${i%R2*}R1.fastq
done

#### Remove useless files
rm outdir/three_prime/3tail_read_with_tag/*out
rm outdir/three_prime/fastq/*unique.out
mv outdir/three_prime/fastq/*out outdir/three_prime/3tail_read_with_tag_other_strand/



## 3. Trim A10 at R2 reads

for i in `ls outdir/three_prime/3tail_read_with_tag_other_strand`
do
        python script/find_A10_and_trim.py  -i outdir/three_prime/3tail_read_with_tag_other_strand/${i} -o outdir/three_prime/3tail_read_with_tag_other_strand_withA10_trim/${i}_withA10_trim
done


## 4. Mapping

for i in `ls outdir/three_prime/3tail_read_with_tag_other_strand_withA10_trim/`
do
        STAR --runThreadN 24 --genomeDir ${star_dir} --genomeLoad NoSharedMemory --readFilesIn outdir/three_prime/3tail_read_with_tag_other_strand_withA10_trim/${i} --outFileNamePrefix outdir/three_prime/mapping_outdir/${i}_ --outSAMtype SAM --outFilterMultimapNmax 1 --outFilterScoreMinOverLread 0.6 --outFilterMatchNminOverLread 0.6
done







for i in `ls outdir/three_prime/mapping_outdir |grep "sam"|grep "R1"`
do
### The first read count
        a=$(wc -l outdir/three_prime/mapping_outdir/${i}|awk '{print $1}')
        echo ${a}

### The second read count
        b=$(wc -l outdir/three_prime/mapping_outdir/${i%%R1*}R2.fastq-common.out_withA10_trim_Aligned.out.sam|awk '{print $1}')
        echo ${b}

### Remove useless files
        if [ ${a} -gt ${b} ]; then
                rm outdir/three_prime/mapping_outdir/${i%%R1*}R2*
        else
                rm outdir/three_prime/mapping_outdir/${i%%R1*}R1*
        fi
done




## 6. Convert SAM to BED

for i in `ls outdir/three_prime/mapping_outdir | grep "sam$"`
do
### Add header and convert to bam
        samtools view -b -T ${fa_file} outdir/three_prime/mapping_outdir/${i} | samtools view -b > outdir/three_prime/final_out/${i}_add_header.bam

### Sort
        samtools sort outdir/three_prime/final_out/${i}_add_header.bam -o outdir/three_prime/final_out/${i}_add_header_sorted.bam

### Build bam index for visualization
        samtools index outdir/three_prime/final_out/${i}_add_header_sorted.bam

### Convert bam into bed
        bedtools bamtobed -i outdir/three_prime/final_out/${i}_add_header_sorted.bam > outdir/three_prime/final_out/${i}_add_header_sorted.bed
done




## 7. Remove reads mapped to tRNA and rRNA
for i in `ls  outdir/three_prime/final_out |grep "bed$"`
do
        bedtools subtract -a outdir/three_prime/final_out/${i} -b reference/gencode_hg38_tRNA_rRNA_gene.bed > outdir/three_prime/final_out/${i%.*}_remove_trRNA.bed
done


## 8. find barcode and UMI

for i in `ls outdir/three_prime/final_out | grep "sorted_remove_trRNA.bed$"`
do

        if [ ${i#*.R} == "1.fastq-common.out_withA10_trim_Aligned.out.sam_add_header_sorted_remove_trRNA.bed" ]; then
                python2 script/annotate_UMI_v1.py -N 18 -n 8 -F outdir/three_prime/fastq/${i%%.R*}.R2.fastq -ID outdir/three_prime/final_out/${i} -O outdir/three_prime/annote/${i}.annote
        fi
        if [ ${i#*.R} == "2.fastq-common.out_withA10_trim_Aligned.out.sam_add_header_sorted_remove_trRNA.bed" ]; then
                python2 script/annotate_UMI_v1.py -N 18 -n 8 -F outdir/three_prime/fastq/${i%%.R*}.R1.fastq -ID outdir/three_prime/final_out/${i} -O outdir/three_prime/annote/${i}.annote
        fi
done


## 9. collapse

for i in `ls outdir/three_prime/annote | grep "annote$"`
do
        Rscript script/collapse_UMI_TES.R  outdir/three_prime/annote/${i}
done

mv outdir/three_prime/annote/*collapse outdir/three_prime/collapse/



## 10. collapse 6 and change name

for i in `ls outdir/three_prime/collapse | grep "collapse$"`
do
        awk '{FS=" "}{print $1"\t"$2"\t"$3"\t"$4"\t"$5"\t"$6}' outdir/three_prime/collapse/${i} > outdir/three_prime/collapse/${i}.6
        mv outdir/three_prime/collapse/${i}.6 outdir/three_prime/collapse/sampleTES_TKD.bed
done

