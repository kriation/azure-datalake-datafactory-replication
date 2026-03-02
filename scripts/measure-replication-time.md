# Measuring Replication Time for Azure File Share and Data Lake

This script helps you measure the time it takes for a file to replicate from the source region to the destination region, after it appears in the source account.

## Usage

```sh
./measure-replication-time.sh -t <type> -f <filename> [options]
```

### Required Arguments
- `-t TYPE`           Type of storage: `fileshare` or `datalake`
- `-f FILENAME`       Name of the file to check (e.g., randomfile_1_xxxxxxxx.bin)

### Common Options
- `-s SOURCE_ACCOUNT`   Source storage account name
- `-d DEST_ACCOUNT`     Destination storage account name
- `-g SOURCE_RG`        Source resource group
- `-h DEST_RG`          Destination resource group
- `-S SOURCE_SHARE`     Source file share or filesystem
- `-D DEST_SHARE`       Destination file share or filesystem
- `--interval` or `-y`  Polling interval in seconds (default: 10)
- `--max-wait` or `-m`  Max wait time in seconds (default: 1800)

### Example: File Share
```sh
./measure-replication-time.sh -t fileshare -f randomfile_1_abc12345.bin \
  -s stdemoeastus2 -d stdemoeastcanada -g rg-demo-eastus2 -h rg-demo-canadaeast \
  -S fileshare -D fileshare --interval 10 --max-wait 1800
```

### Example: Data Lake
```sh
./measure-replication-time.sh -t datalake -f randomfile_1_abc12345.bin \
  -s stdldemoeastus2 -d stdldemocanadaeast -g rg-demo-eastus2 -h rg-demo-canadaeast \
  -S fsdleastus2 -D fsdlcanadaeast --interval 10 --max-wait 1800
```

## Output
- The script prints the replication time to the console.
- Results are appended to `replication_results.csv` in the current directory, with columns:
  - filename, type, start_time (epoch), end_time (epoch), duration_seconds

## Notes
- The script only measures the time from when the file is confirmed present in the source to when it appears in the destination.
- Make sure you have Azure CLI access and permissions for both source and destination accounts.
- For best results, use files created by the provided population scripts.
