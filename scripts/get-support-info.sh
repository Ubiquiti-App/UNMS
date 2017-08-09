outdir=~unms/supportinfo
outfile=~unms/supportinfo.tar.gz

rm -rf "${outdir}"
mkdir -p "${outdir}"

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
rm -rf "${outdir}"

echo Saved to "${outfile}"