from google.cloud import storage
import datetime
import subprocess

def backup_mongo(request):
    # GCS setup
    bucket_name = "mongo-backups-bucket"  # Replace with your bucket name
    client = storage.Client()
    bucket = client.bucket(bucket_name)
    
    # Define backup filename with a timestamp
    timestamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_name = f"mongo_backup_{timestamp}.gz"
    
    # Run MongoDB dump command
    subprocess.run(["mongodump", "--archive=/tmp/backup.gz", "--gzip"], check=True)
    
    # Upload backup to GCS
    blob = bucket.blob(backup_name)
    blob.upload_from_filename("/tmp/backup.gz")
    
    return f"Backup {backup_name} created in {bucket_name}."
