package shapes;

import src.DtsObject;

class SuperSpeed extends DtsObject {
	public function new() {
		super();
		this.dtsPath = "data/shapes/items/superspeed.dts";
		this.isCollideable = false;
		this.isTSStatic = false;
		this.identifier = "SuperSpeed";
	}
}