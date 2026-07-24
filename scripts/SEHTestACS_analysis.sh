#! /usr/bin/bash

#SBATCH --partition=cpu-single
#SBATCH --ntasks=1
#SBATCH --time=00:10:00
#SBATCH --mem=100gb

module load math/R
module load devel/miniforge

conda activate r_env

Rscript -e "rmarkdown::render('SEHTestACS4_analyses.Rmd')"
