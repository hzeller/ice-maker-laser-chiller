TARGETS=baseplate.stl display-holder.stl \
        hose-through.stl pump-holder.stl

all: $(TARGETS)

%.stl: %.scad
	openscad -o $@ $^

clean:
	rm -f $(TARGETS)
