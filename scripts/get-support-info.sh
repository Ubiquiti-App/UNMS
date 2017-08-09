outdir=~unms/supportinfo
outfile=~unms/supportinfo.tar.gz

rm -rf "${outdir}"
mkdir -p "${outdir}"

if [[ "$@" == "--restart" ]]; then
    echo "Restarting UNMS..."
    docker-compose -p unms -f ~unms/app/docker-compose.yml down >"${outdir}/restart.txt"
    docker-compose -p unms -f ~unms/app/docker-compose.yml up -d >>"${outdir}/restart.txt"
    echo "Waiting for 30s..."
    sleep 30
fi

echo "Gathering support info..."

{
  docker -v
  echo
  docker-compose -v
  echo
  docker ps -a
  echo
  docker network ls
  echo
  ps aux | grep docker-proxy
  echo
  docker exec unms ps aux
  echo
  docker exec unms netstat -l
} >"${outdir}/info.txt"

docker ps -a --format "{{ .Names }}" --filter "name=unms" | xargs docker inspect >"${outdir}/containers.txt"
docker network ls --format "{{ .Name }}" --filter "name=unms" | xargs docker network inspect >"${outdir}/networks.txt"

cp ~unms/data/update/* "${outdir}/"

find ~unms/data/logs/* -type f -mtime -1 -exec cp {} "${outdir}/" \;

tar -zcf "${outfile}" -C "${outdir}" .
chown unms "${outfile}"
rm -rf "${outdir}"

echo Saved to "${outfile}"