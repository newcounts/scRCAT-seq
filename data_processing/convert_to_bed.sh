#!/bin/bash

#set -e

genome_fa=$1
star_dir=$2
fq_dir=$3
outdir=$4


if [[ ! -n "$genome_fa" || ! -n "$star_dir" || ! -n "$fq_dir" || ! -n "$outdir" ]]; then
    echo "Error: no enough variable!
This script is used to  process the data generated by scCAT-seq. Fastq file is needed and the output file format is BED.
Usage:
    sh $0 <genome fa file> <STAR index> <fastq file dir> <output dir>
    # for example:
    sh $0 ~/index/hg38/hg38.fa ~/index/hg38_STAR/ ~/fastq/ ~/scCAT_seq/
    # Caution: file in <fastq file dir> must be fastq type, not fastq.gz! Pair-end files are needed!
    "
    exit
fi








#Code in this directory is used to process the data generated by scCAT-seq, C1 CAGE, BAT-seq, etc. `Fastq` file is needed and the output file format is `BED`. Each Row represents read in corresponding position.

#Then `BED` file as input is needed to call peak using `CAGEr` R package.



# Data processing for 5' data

#The workflows of data of scCAT-seq 5', C1 CAGE, C1 STRT and Arguel et al. are similar. Here is the scCAT-seq 5' data processing workflow. To see detail imformation of other data processing, please see `C1_CAGE_5_data_processing.sh`, `C1_STRT_5_data_processing.sh` and `Arguel_et_al_5_data_processing.sh`.

#We have uploaded test data. Reader can download at [here](https://drive.google.com/open?id=1t8oLqAIWWy32yf5g3NOfKm10-i0pBITy) and [here](https://drive.google.com/open?id=1Z4xEVmkip3aq56Jp5k-0qBLmZ9oR-Lyk).

## 0. Preparation


#Before process the data, we bulid some directory and move the script to `script_and_log` and `fastq` directory:


#### Create directory
mkdir ${outdir}
mkdir ${outdir}/five_pirme
mkdir ${outdir}/five_pirme/5cap_read_with_tag
mkdir ${outdir}/five_pirme/trim_TSO
mkdir ${outdir}/five_pirme/mapping_output
mkdir ${outdir}/five_pirme/final_out
mkdir ${output}/five_pirme/annote/
mkdir ${output}/five_pirme/collapse/


## 1. Find reads with TSO primer

#Reads with TSO primer sequence at 5' are considered to further processing. TSO primer in scCAT-seq data is `GTGGTATCAACGCAGAGTACATGGG`.


for i in `ls ${fq_dir}|grep "8N"`
do
        cat ${fq_dir}/${i} | paste - - - - | grep -E $'\t'"GTGGTATCAACGCAGAGTGCAATGAAGTCGCAGGGTTG[A|G|C|T][A|G|C|T][A|G|C|T][A|G|C|T][A|G|C|T][A|G|C|T][A|G|C|T][A|G|C|T]GGG" | awk -v FS="\t" -v OFS="\n" '{print $1, $2, $3, $4}' > ${outdir}/five_pirme/5cap_read_with_tag/${i}_with_tag.fq
done


#Output files are stored in `${outdir}/five_pirme/5cap_read_with_tag/`.


## 2. Trim TSO primer

#To trim TSO primer, we run:


for i in `ls ${outdir}/five_pirme/5cap_read_with_tag`
do
        cutadapt -u 49 -j 40 -o ${outdir}/five_pirme/trim_TSO/${i}.trimed.remainGGG ${outdir}/five_pirme/5cap_read_with_tag/${i}
done


#In this step, we trim TSO primer.
#Output files are stored in `${outdir}/five_pirme/trim_TSO/`.



## 3. Mapping

#For mapping, we run:


for i in `ls ${outdir}/five_pirme/trim_TSO/`
do
        STAR --runThreadN 24 --genomeDir ${star_dir} --genomeLoad LoadAndKeep --readFilesIn ${outdir}/five_pirme/trim_TSO/${i} --outFileNamePrefix ${outdir}/five_pirme/mapping_output/${i}_ --outSAMtype SAM --outFilterMultimapNmax 1 --outFilterScoreMinOverLread 0.6 --outFilterMatchNminOverLread 0.6
done


#Output files are stored in `${outdir}/five_pirme/mapping_output/`.


## 4. remove useless file

for i in `ls ${outdir}/five_pirme/mapping_output |grep "sam"|grep "R1"`
do
#### The first read count
        a=$(wc -l ${outdir}/five_pirme/mapping_output/${i}|awk '{print $1}')
        echo ${a}

#### The second read count
        b=$(wc -l ${outdir}/five_pirme/mapping_output/${i%%R1*}R2.fastq_with_tag.fq.trimed.remainGGG_Aligned.out.sam|awk '{print $1}')
        echo ${b}

#### Remove useless files
        if [ ${a} -gt ${b} ]; then
                rm ${outdir}/five_pirme/mapping_output/${i%%R1*}R2*
        else
                rm ${outdir}/five_pirme/mapping_output/${i%%R1*}R1*
        fi
done




## 5 convert to bed

#As `BED` format file can be used as input for `CAGEr` R package, we convert `SAM` to `BED`:


for i in `ls ${outdir}/five_pirme/mapping_output | grep "sam$"`
do
/zjw/nc/demogithub/#### Add header and convert to bam
        samtools view -b -T ${genome_fa} ${outdir}/five_pirme/mapping_output/${i} | samtools view -b >  ${outdir}/five_pirme/final_out/${i}_add_header.bam

#### Sort
        samtools sort ${outdir}/five_pirme/final_out/${i}_add_header.bam -o ${outdir}/five_pirme/final_out/${i}_add_header_sorted.bam

#### Build bam index for visualization
        samtools index ${outdir}/five_pirme/final_out/${i}_add_header_sorted.bam

#### Convert bam into bed
        bedtools bamtobed -i ${outdir}/five_pirme/final_out/${i}_add_header_sorted.bam > ${outdir}/five_pirme/final_out/${i}_add_header_sorted.bed
done


#Output files are stored in `${outdir}/five_pirme/final_out/`.



## 6. Remove reads mapped to tRNA and rRNA

#Reads that mapped at tRNA and rRNA position are discarded:

for i in `ls  ${outdir}/five_pirme/final_out |grep "bed$"`
do
        bedtools subtract -a ${outdir}/five_pirme/final_out/${i} -b ~/zjw/annotation/gencode_hg38_tRNA_rRNA_gene.bed > ${outdir}/five_pirme/final_out/${i%.*}_remove_trRNA.bed
done


## 7. find barcode and UMI

for i in `ls ${output}/five_pirme/final_out | grep "sorted_remove_trRNA.bed$"`
do
        python annotate_UMI_v1.py -N 38 -n 8 -F ${fq_dir}/${i%%_with*} -ID ${output}/five_pirme/final_out/${i} -O ${outpuu}/five_pirme/annote/${i}.annote
done


## 8. collapse

for i in `ls ${output}/five_pirme/annote | grep "annote$"`
do
        Rscript collapse_UMI_5.R  ${output}/five_pirme/annote/${i}
done

mv ${output}/five_pirme/annote/*collapse ${output}/five_pirme/annote/collapse/


## 9. collapse 6 and change name

for i in `ls ${output}/five_pirme/collapse | grep "collapse$"`
do
        awk '{FS=" "}{print $1"\t"$2"\t"$3"\t"$4"\t"$5"\t"$6}' ${output}/five_pirme/collapse/${i} > ${output}/five_pirme/collapse/${i}.6
	mv ${output}/five_pirme/collapse/${i}.6 > ${output}/five_pirme/collapse/${i%%L3*}_5_TKD.bed 
done


































# Data processing for 3' data

#The workflows of data of scCAT-seq 3' and BAT-seq are similar. Here is the scCAT-seq 5' data processing workflow. To see detail imformation of BAT-seq data processing, please see `BAT-seq_3_data_processing.sh`.

## 0. Preparation

#Before process the data, we bulid some directory and move the script to `script_and_log` directory:


#### Create directory
mkdir ${outdir}/three_pirme
mkdir ${outdir}/three_pirme/3tail_read_with_tag
mkdir ${outdir}/three_pirme/3tail_read_with_tag_other_strand
mkdir ${outdir}/three_pirme/3tail_read_with_tag_other_strand_withA10_remain_A5
mkdir ${outdir}/three_pirme/mapping_output
mkdir ${outdir}/three_pirme/final_out
mkdir ${output}/three_pirme/annote/
mkdir ${output}three_pirme/collapse/


## 1. Find reads with oligo(dT) primer

#Reads with oligo(dT) primer sequence at 5'. We define reads with oligo(dT) primer sequence at 5' as R1 reads. Oligo(dT) primers in scCAT-seq data are listed in `sample_list_tag.txt`:

for i in `ls ${fq_dir}|grep "8N"`
do
        cat ${fq_dir}/${i} | paste - - - - | grep -E $'\t'"GTGGTATCAACGCAGAGT[A|G|C|T][A|G|C|T][A|G|C|T][A|G|C|T][A|G|C|T][A|G|C|T][A|G|C|T][A|G|C|T]CTAAGCCTTTTT" | awk -v FS="\t" -v OFS="\n" '{print $1, $2, $3, $4}' > ${outdir}/three_pirme/3tail_read_with_tag/${i}_with_tag
done



#Output files are stored in `${outdir}/three_pirme/3tail_read_with_tag/`.

## 2. Find R2 reads

#Perl script `cmpfastq_pe.pl` is used to find R2 reads which its corresponding R1 reads with oligo(dT) primes:


#### Compare R1_with_tag to R2
for i in `ls ${outdir}/three_pirme/3tail_read_with_tag/ | grep "R1.fastq_with_tag$"`
do
        perl cmpfastq_pe.pl ${outdir}/three_pirme/3tail_read_with_tag/${i} ${fq_dir}/${i%R1*}R2.fastq
done

#### Compare R2_with_tag to R1
for i in `ls ${outdir}/three_pirme/3tail_read_with_tag/ | grep "R2.fastq_with_tag$"`
do
        perl cmpfastq_pe.pl ${outdir}/three_pirme/3tail_read_with_tag/${i} ${fq_dir}/${i%R2*}R1.fastq
done

#### Remove useless files
rm ${outdir}/three_pirme/3tail_read_with_tag/*out
rm ${fq_dir}/*unique.out
mv ${fq_dir}/*out ${outdir}/three_pirme/3tail_read_with_tag_other_strand/


#Output files are stored in `${outdir}/three_pirme/3tail_read_with_tag_other_strand/`.

## 3. Trim A10 at R2 reads

#To trim polyA at 3', we run:


for i in `ls ${outdir}/three_pirme/3tail_read_with_tag_other_strand`
do
        python find_A10_and_trim.py  -i ${outdir}/three_pirme/3tail_read_with_tag_other_strand/${i} -o ${outdir}/three_pirme/3tail_read_with_tag_other_strand_withA10_remain_A5/${i}_withA10_remain_A5
done


#Output files are stored in `${outdir}/three_pirme/3tail_read_with_tag_other_strand_withA10_remain_A5/`.

## 4. Mapping

#For Mapping, we run:


for i in `ls ${outdir}/three_pirme/3tail_read_with_tag_other_strand_withA10_remain_A5/`
do
        STAR --runThreadN 24 --genomeDir ${star_dir} --genomeLoad LoadAndKeep --readFilesIn ${outdir}/three_pirme/3tail_read_with_tag_other_strand_withA10_remain_A5/${i} --outFileNamePrefix ${outdir}/three_pirme/mapping_output/${i}_ --outSAMtype SAM --outFilterMultimapNmax 1 --outFilterScoreMinOverLread 0.6 --outFilterMatchNminOverLread 0.6
done


#Output files are stored in `${outdir}/three_pirme/mapping_output/`.


## 5. Remove useless file


for i in `ls ${outdir}/three_pirme/mapping_output |grep "sam"|grep "R1"`
do
### The first read count
        a=$(wc -l ${outdir}/three_pirme/mapping_output/${i}|awk '{print $1}')
        echo ${a}

### The second read count
        b=$(wc -l ${outdir}/three_pirme/mapping_output/${i%%R1*}R2.fastq-common.out_withA10_remain_A5_Aligned.out.sam|awk '{print $1}')
        echo ${b}

### Remove useless files
        if [ ${a} -gt ${b} ]; then
                rm ${outdir}/three_pirme/mapping_output/${i%%R1*}R2*
        else
                rm ${outdir}/three_pirme/mapping_output/${i%%R1*}R1*
        fi
done


## 6. Convert SAM to BED

#As `BED` format file can be used as input for `CAGEr` R package, we generate `SAM` to `BED`:


for i in `ls ${outdir}/three_pirme/mapping_output | grep "sam$"`
do
### Add header and convert to bam
        samtools view -b -T ${genome_fa} ${outdir}/three_pirme/mapping_output/${i} | samtools view -b > ${outdir}/three_pirme/final_out/${i}_add_header.bam

### Sort
        samtools sort ${outdir}/three_pirme/final_out/${i}_add_header.bam -o ${outdir}/three_pirme/final_out/${i}_add_header_sorted.bam

### Build bam index for visualization
        samtools index ${outdir}/three_pirme/final_out/${i}_add_header_sorted.bam

### Convert bam into bed
        bedtools bamtobed -i ${outdir}/three_pirme/final_out/${i}_add_header_sorted.bam > ${outdir}/three_pirme/final_out/${i}_add_header_sorted.bed
done


#Output files are stored in `${outdir}/three_pirme/final_out/`.



## 7. Remove reads mapped to tRNA and rRNA

#Reads that mapped at tRNA and rRNA position are discarded:

for i in `ls  ${outdir}/three_pirme/final_out |grep "bed$"`
do
        bedtools subtract -a ${outdir}/three_pirme/final_out/${i} -b ~/zjw/annotation/gencode_hg38_tRNA_rRNA_gene.bed > ${outdir}/three_pirme/final_out/${i%.*}_remove_trRNA.bed
done



## 8. find barcode and UMI

for i in `ls ${output}/three_pirme/final_out | grep "sorted_remove_trRNA.bed$"`
do

        if [ ${i#*.R} == "1.fastq-common.out_withA10_remain_A5_Aligned.out.sam_add_header_sorted_remove_trRNA.bed" ]; then
		python annotate_UMI_v1.py -N 18 -n 8 -F ${fq_dir}/${i%%.R*}.R2.fastq -ID ${output}/three_pirme/final_out/${i} -O ${output}/three_pirme/annote/${i}.annote
 	fi
	if [ ${i#*.R} == "2.fastq-common.out_withA10_remain_A5_Aligned.out.sam_add_header_sorted_remove_trRNA.bed" ]; then
 		python annotate_UMI_v1.py -N 18 -n 8 -F ${fq_dir}/${i%%.R*}.R1.fastq -ID ${output}/three_pirme/final_out/${i} -O ${output}/three_pirme/annote/${i}.annote
	fi
done


## 9. collapse

for i in `ls ${output}/three_pirme/annote | grep "annote$"`
do
        Rscript collapse_UMI_5.R  ${output}/three_pirme/annote/${i}
done

mv ${output}/three_pirme/annote/*collapse ${output}/three_pirme/annote/collapse/


## 10. collapse 6 and change name

for i in `ls ${output}/three_pirme/collapse | grep "collapse$"`
do
        awk '{FS=" "}{print $1"\t"$2"\t"$3"\t"$4"\t"$5"\t"$6}' ${output}/three_pirme/collapse/${i} > ${output}/three_pirme/collapse/${i}.6
        mv ${output}/three_pirme/collapse/${i}.6 > ${output}/three_pirme/collapse/${i%%L3*}_3_TKD.bed
done

