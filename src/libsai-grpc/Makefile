PROTOS = $(wildcard dataplane/proto/sai/*.proto)
PROTO_SRC = $(patsubst dataplane/proto/sai/%.proto, dataplane/proto/sai/%.pb.cc, $(PROTOS))
PROTO_GRPC_SRC = $(patsubst dataplane/proto/sai/%.proto, dataplane/proto/sai/%.grpc.pb.cc, $(PROTOS))
PROTO_OBJ = $(patsubst dataplane/proto/sai/%.proto, dataplane/proto/sai/%.pb.o, $(PROTOS))
GRPC_OBJ = $(patsubst dataplane/proto/sai/%.proto, dataplane/proto/sai/%.grpc.pb.o, $(PROTOS))
SAI_SRC = $(wildcard dataplane/standalone/sai/*.cc)
SAI_OBJ = $(patsubst dataplane/standalone/sai/%.cc, dataplane/standalone/sai/%.o, $(SAI_SRC))

all: lucius-libsai-bookworm

$(PROTO_SRC) $(PROTO_GRPC_SRC) &:
	protoc dataplane/proto/sai/*.proto --cpp_out=. --grpc_out=. --plugin=protoc-gen-grpc=`which grpc_cpp_plugin` --experimental_allow_proto3_optional

dataplane/proto/sai/%.pb.o: dataplane/proto/sai/%.pb.cc
	g++ -fPIC -c $< -I . -o $@

dataplane/proto/sai/%.grpc.pb.o:  dataplane/proto/sai/%.grpc.pb.cc
	g++ -fPIC -c $< -I . -o $@

dataplane/standalone/sai/%.o: dataplane/standalone/sai/%.cc $(PROTO_SRC)
	g++ -fPIC -c $< -o $@ -I . -I external/com_github_opencomputeproject_sai -I external/com_github_opencomputeproject_sai/inc  -I external/com_github_opencomputeproject_sai/experimental

libsai.so: $(PROTO_OBJ) $(GRPC_OBJ) $(SAI_OBJ)
	g++ -fPIC -o libsai.so -shared entrypoint.cc dataplane/proto/sai/*.o dataplane/standalone/sai/*.o -lglog -lprotobuf -lgrpc++ -I . -I external/com_github_opencomputeproject_sai -I external/com_github_opencomputeproject_sai/inc -I external/com_github_opencomputeproject_sai/experimental

lucius-libsai-bookworm:
	DOCKER_BUILDKIT=1 docker build . -f Dockerfile.saibuilder -t lemming-libsai:latest
	docker create --name libsai-temp lemming-libsai:latest
	docker cp libsai-temp:/build/libsai.so ./libsai.so
	docker rm libsai-temp

install: lucius-libsai-bookworm
	echo "Inside lucius_sai"
	install -D ./libsai.so $(DESTDIR)/usr/lib/x86_64-linux-gnu/libsaivs.so.0.0.0
	cd $(DESTDIR)/usr/lib/x86_64-linux-gnu && ln -s libsaivs.so.0.0.0 libsaivs.so.0

clean:
	-rm -f dataplane/proto/sai/*.cc dataplane/proto/sai/*.h dataplane/proto/sai/*.o
	-rm -f dataplane/standalone/sai/*.o
	-rm -f libsai.so

.PHONY: clean install
