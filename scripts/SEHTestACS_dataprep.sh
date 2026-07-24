#! /usr/bin/bash

#SBATCH --partition=cpu-single
#SBATCH --ntasks=1
#SBATCH --time=00:15:00
#SBATCH --mem=50gb

module load math/R
module load devel/miniforge

conda activate r_env

Rscript SEHTestACS2a_dataprepACS.R
Rscript SEHTestACS2b_dataprepPUMS.R
Rscript SEHTestACS3_citylevel.R
